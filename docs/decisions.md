# Nos choix techniques

Retour au [README](../README.md).

Pour chaque choix : ce qu'on a fait, pourquoi, et ce qu'on n'a pas choisi.

## D1. Terraform pour le cluster, Helm pour l'application

**Ce qu'on fait :** Terraform crée seulement le cluster GKE. Helm installe et met à jour
l'application.

**Pourquoi :** le cluster est créé une fois par session de lab, alors que l'application change
souvent et on veut pouvoir revenir en arrière avec `helm rollback`. En plus, en local il n'y a
pas de Terraform, et on veut le même chart partout.

**Pas choisi :** installer le chart depuis Terraform (`helm_release`). Ça mélangerait les deux et
un problème dans l'application pourrait bloquer Terraform.

## D2. Stratégie Recreate pour le Redis leader

**Ce qu'on fait :** le Deployment du leader est en `Recreate`. Le frontend et les followers sont
en `RollingUpdate` avec `maxSurge: 1` et `maxUnavailable: 0`.

**Pourquoi Recreate pour le leader :**

- son volume est en `ReadWriteOnce` : un seul nœud peut l'utiliser en écriture ;
- un seul Redis doit écrire dans `/data` à la fois, sinon le fichier peut être abîmé ;
- avec un RollingUpdate, Kubernetes démarre le nouveau pod **avant** d'arrêter l'ancien. Si le
  nouveau pod est sur un autre nœud, il reste bloqué parce que le disque est encore attaché à
  l'ancien nœud. La mise à jour ne se termine jamais.

Avec Recreate, l'ancien pod s'arrête d'abord, puis le nouveau démarre et récupère le disque.

**Le prix à payer :** pendant quelques secondes on ne peut pas écrire de message. La lecture
marche toujours grâce aux followers. Pour un livre d'or, ce n'est pas grave.

**Pourquoi RollingUpdate pour les autres :** ils n'ont pas de données sur disque. Avec
`maxUnavailable: 0`, un nouveau pod doit être prêt avant qu'on enlève un ancien, donc il n'y a
pas de coupure.

## D3. Persistance Redis : mode AOF

**Ce qu'on fait :** dans `redis.conf` : `dir /data`, `appendonly yes` et `appendfsync always`.

**Pourquoi :** le client ne veut perdre aucun message. En mode AOF, Redis ajoute chaque écriture à
la fin du fichier `appendonly.aof`. Au redémarrage, il relit ce fichier et retrouve tout. Avec
`appendfsync always`, chaque message est écrit sur le disque tout de suite. Ça ralentit un peu
Redis, mais un livre d'or reçoit peu de messages.

**Pas choisi :**

- le mode RDB seul (une photo des données de temps en temps) : on perd ce qui a été écrit depuis
  la dernière photo ;
- `appendfsync everysec` (le réglage par défaut) : on peut perdre jusqu'à une seconde de messages
  en cas de crash.

## D4. Les probes

| Composant | Type | Readiness | Liveness |
|---|---|---|---|
| frontend | `httpGet` sur `/`, port `http` | après 5s, toutes les 5s, timeout 3s, 3 échecs | après 15s, toutes les 10s, timeout 3s, 3 échecs |
| Redis leader et followers | `exec redis-cli ping` | après 5s, toutes les 5s, timeout 2s, 3 échecs | après 15s, toutes les 10s, timeout 2s, 3 échecs |

**Différence entre les deux :**

- la **readiness** dit si le pod peut recevoir du trafic. Si elle échoue, le Service n'envoie plus
  de requêtes au pod, mais on ne le redémarre pas ;
- la **liveness** dit si le conteneur est bloqué. Si elle échoue, Kubernetes redémarre le
  conteneur.

**Pourquoi ces valeurs :**

- Apache et Redis démarrent en environ 1 seconde, donc 5 secondes d'attente suffisent pour la
  readiness ;
- la liveness commence plus tard (15s) et teste moins souvent (10s). Sinon, un pod un peu lent à
  démarrer serait redémarré en boucle. Par exemple Redis doit d'abord relire son fichier AOF ;
- 3 échecs de suite avant d'agir, pour ne pas réagir à un seul test raté ;
- timeout de 2 secondes pour Redis (un `PING` répond en quelques millisecondes) et 3 secondes pour
  la page PHP.

**Pourquoi `redis-cli ping` plutôt que `tcpSocket` :** `tcpSocket` vérifie juste que le port 6379
est ouvert. Mais pendant qu'il relit son fichier AOF, Redis accepte les connexions sans pouvoir
répondre aux commandes. `redis-cli ping` attend une vraie réponse `PONG`, c'est plus fiable.

## D5. Les ressources (requests et limits)

- **requests** = ce que Kubernetes réserve pour le conteneur.
- **limits** = le maximum. Au-dessus en CPU le conteneur est ralenti, au-dessus en mémoire il
  est tué (OOMKilled).

| Composant | dev | staging | prod |
|---|---|---|---|
| frontend | 50m/64Mi, max 200m/128Mi | 100m/128Mi, max 250m/256Mi | 150m/192Mi, max 300m/384Mi |
| Redis leader | 50m/64Mi, max 200m/128Mi | 100m/128Mi, max 250m/256Mi | 200m/256Mi, max 500m/512Mi |
| Redis followers | 50m/64Mi, max 200m/128Mi | 100m/128Mi, max 250m/256Mi | 150m/192Mi, max 300m/384Mi |

(100m = 0,1 CPU)

**Pourquoi :**

- on est partis des valeurs du tutoriel (100m et 100Mi) ;
- on a mis 128Mi au lieu de 100Mi parce que GKE Autopilot demande au moins 1 Gi de mémoire par CPU.
  Sinon il modifie lui-même les valeurs ;
- en dev il n'y a presque pas de trafic, donc on réduit pour économiser ;
- staging utilise les valeurs par défaut, proches de la prod, pour que les tests soient réalistes ;
- en prod on met plus, surtout pour le leader : il reçoit toutes les écritures et Redis garde tout
  en mémoire.

## D6. Les noms des objets et des Services

**Ce qu'on fait :**

- les Deployments, ConfigMaps et le PVC ont un nom fabriqué par `_helpers.tpl` :
  `<release>-guestbook-<composant>`, par exemple `stack-prod-guestbook-redis-leader` ;
- les Services gardent des noms simples : `frontend`, `redis-leader`, `redis-follower`.

**Pourquoi les Services Redis ne changent pas de nom :** on a regardé le code des images.

- Dans le frontend (`guestbook.php`), si `GET_HOSTS_FROM` vaut `dns`, le PHP se connecte
  directement à l'hôte `redis-leader` pour écrire et `redis-follower` pour lire.
- Dans le follower (`run.sh`), Redis démarre avec `--replicaof redis-leader 6379`.

Ces noms sont écrits en dur dans les images, donc nos Services doivent s'appeler exactement
`redis-leader` et `redis-follower`. Le DNS de Kubernetes fait le reste. Comme chaque environnement
est dans son namespace, avoir le même nom dans dev et prod ne pose pas de problème.

Les noms sont quand même des valeurs du chart (`redisLeader.service.name`...), avec un commentaire
dans `values.yaml` qui dit de ne pas les changer.

**Pas choisi :** `GET_HOSTS_FROM=env`. Dans ce cas le PHP lit l'adresse de Redis dans des variables
que Kubernetes ajoute au pod, mais seulement si le Service existait avant le pod. C'est moins
fiable.

## D7. Labels et selectors

Tous les labels viennent de `_helpers.tpl`, aucun n'est écrit à la main dans les templates.

Les selectors utilisent seulement `app.kubernetes.io/name`, `app.kubernetes.io/instance` et
`app.kubernetes.io/component`. On n'y met **pas** la version (`app.kubernetes.io/version` ou
`helm.sh/chart`) : le selector d'un Deployment ne peut plus être modifié après la création. Si la
version était dedans, le premier `helm upgrade` avec une nouvelle version de chart échouerait.

## D8. StorageClass vide = classe par défaut

`redisLeader.persistence.storageClass` vaut `""`. Dans ce cas le template n'écrit pas du tout le
champ `storageClassName` (avec un `with` dans le template).

C'est important : si on écrit `storageClassName: ""` dans un PVC, Kubernetes comprend "aucune
StorageClass" et le PVC reste en `Pending`. Quand le champ n'est pas là, Kubernetes utilise la
classe par défaut du cluster : `standard` sur minikube et `standard-rwo` sur GKE. Le même chart
marche donc aux deux endroits.

## D9. Différence local / cloud pour le Service du frontend

**Ce qu'on fait :** dans les fichiers `values-<ENV>.yaml` le type est `LoadBalancer`. Sur GKE,
pour la phase de test, on ajoute `--set frontend.service.type=ClusterIP` au `helm install`. Ensuite
on relance `helm upgrade` sans le `--set`, et on revient à `LoadBalancer`.

**Pourquoi :** c'est une seule option dans la commande, facile à voir et à enlever.

**Pas choisi :** un fichier `values-gke.yaml` en plus, juste pour une valeur.

À savoir : un `helm upgrade` repart des fichiers de valeurs. Un `--set` oublié est donc annulé au
prochain upgrade. C'est pour ça que tout changement qui doit rester se fait dans le fichier.

## D10. State Terraform en local

**Ce qu'on fait :** le fichier `terraform.tfstate` reste sur le poste (ou dans Cloud Shell). Il
est dans le `.gitignore`.

**Pourquoi :** le projet du lab est supprimé à la fin de chaque session, et une seule personne
lance Terraform à la fois.

**Les risques :** si on perd le fichier, Terraform ne sait plus que le cluster existe (il faut le
supprimer à la main dans la console). Si deux personnes lancent `apply` en même temps, rien ne les
en empêche.

**En entreprise :** on mettrait le state dans un bucket Google Cloud Storage (backend `gcs`), qui
gère le verrouillage et garde l'historique.

## D11. On garde .terraform.lock.hcl dans Git

Ce fichier note les versions exactes des providers installés (google 8.9.0, google-beta 8.9.0,
kubernetes 2.38.0, random 3.9.1). En le gardant dans Git, tout le monde installe les mêmes versions
à chaque session, même si une nouvelle version sort entre-temps. Pour mettre à jour :
`terraform init -upgrade`, puis on commit le fichier.

## D12. Le PVC est gardé quand on désinstalle

Le PVC a l'annotation `helm.sh/resource-policy: keep`. Un `helm uninstall` fait par erreur ne
supprime donc pas les messages. Si on réinstalle la même release dans le même namespace, elle
reprend le même PVC.

Par contre il faut supprimer les PVC à la main avant `terraform destroy`, sinon les disques
peuvent rester dans le projet (voir runbook R10).

## D13. Création des namespaces

On utilise `--create-namespace` dans `helm install`. C'est simple et ça marche pareil sur minikube
et sur GKE. Le fichier `k8s/namespaces.yaml` (avec le label `environment`) sert pour la partie
sans Helm. Un namespace créé comme ça n'est pas supprimé par `helm uninstall`, il faut le faire à
la main (runbook R10).

## D14. Un fichier en plus pour les Mac à puce Apple

**Le problème :** les images `gb-frontend` et `gb-redis-follower` de Google n'existent que pour
les puces Intel/AMD. Sur un Mac à puce Apple, on installe un émulateur, ce qui suffit pour le
frontend. Mais Redis plante quand il est émulé (`Segmentation fault`).

**Ce qu'on fait :** le fichier `values-mac.yaml` remplace l'image du follower par l'image Redis
officielle (elle existe pour les deux types de puces) et lui donne la même commande que l'image
de Google : `redis-server --replicaof redis-leader 6379`. On l'ajoute avec un deuxième `-f`,
seulement sur Mac. Le chart reste le même pour tout le monde.

**Pas choisi :** changer l'image du follower pour tout le monde. On garde l'image de référence du
tutoriel, qui a été testée sur GKE.
