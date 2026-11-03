# Architecture

Retour au [README](../README.md).

## 1. Les deux environnements

| | En local | Sur le cloud |
|---|---|---|
| Cluster | minikube avec Docker Desktop | GKE Autopilot créé par Terraform |
| Connexion kubectl | contexte `minikube` | `gcloud container clusters get-credentials` |
| Installation | `helm install` / `helm upgrade` | les mêmes commandes |
| Accès au site | LoadBalancer + `minikube tunnel`, sur 127.0.0.1 | d'abord ClusterIP + `port-forward`, puis LoadBalancer avec une IP publique |
| StorageClass par défaut | `standard` | `standard-rwo` (un disque Google) |

C'est le même chart dans les deux cas, avec les mêmes fichiers de valeurs. Seul le type du Service
du frontend change pendant la phase de test sur GKE.

Terraform crée uniquement le cluster (et un compte de service pour ses nœuds). Helm ne crée rien
dans GCP lui-même. Par contre, quand Helm crée un Service LoadBalancer ou un PVC, GKE crée
automatiquement un load balancer ou un disque dans le projet.

## 2. Les objets d'une release

Exemple pour prod (pour les autres, on remplace `prod` par `dev` ou `staging`) :

| Type | Nom | Rôle |
|---|---|---|
| Deployment | `stack-prod-guestbook-frontend` | le site PHP, 3 pods, RollingUpdate |
| Deployment | `stack-prod-guestbook-redis-leader` | le Redis qui reçoit les écritures, 1 pod, Recreate |
| Deployment | `stack-prod-guestbook-redis-follower` | les copies de Redis pour la lecture, 2 pods |
| Service | `frontend` | LoadBalancer ou ClusterIP, port 8082 |
| Service | `redis-leader` | ClusterIP, port 6379 |
| Service | `redis-follower` | ClusterIP, port 6379 |
| ConfigMap | `stack-prod-guestbook-frontend` | la variable `GET_HOSTS_FROM=dns` |
| ConfigMap | `stack-prod-guestbook-redis-leader` | le fichier `redis.conf` |
| PVC | `stack-prod-guestbook-redis-leader-data` | le volume de 2Gi monté sur `/data` |

Tous les objets ont les mêmes labels : `app.kubernetes.io/name`, `instance`, `version`,
`component`, `part-of`, `managed-by`, `helm.sh/chart`, `environment` et `team`.

Les Services Redis gardent des noms courts parce que les images les cherchent sous ces noms
(voir decisions.md, D6). Comme chaque environnement est dans son namespace, avoir le même nom
dans dev et dans prod ne pose pas de problème.

## 3. Comment les messages circulent

```
  navigateur
      |
      v
  Service frontend --> pods frontend (PHP)  <-- ConfigMap frontend (GET_HOSTS_FROM=dns)
                         |            |
                    écriture        lecture
                         v            v
          Service redis-leader    Service redis-follower
                         v            v
               pod redis-leader <--- pods redis-follower
                         |       (ils copient le leader)
                         |  <-- ConfigMap redis.conf
                         v
               PVC monté sur /data --> disque (StorageClass par défaut)
```

1. Le navigateur appelle la page PHP par le Service `frontend`.
2. Pour écrire un message, le PHP se connecte à `redis-leader`. Pour lire, il se connecte à
   `redis-follower`.
3. Les followers se connectent au leader au démarrage et reçoivent chaque nouveau message.
4. Le leader écrit chaque message dans le fichier `/data/appendonly.aof`, sur le volume.

## 4. Où sont les données

- Les messages sont dans la clé Redis `guestbook`.
- Redis les enregistre dans `/data/appendonly.aof` dans le pod leader.
- `/data` est le PVC `stack-<ENV>-guestbook-redis-leader-data`.
- Derrière le PVC il y a un vrai disque : sur GKE un disque Google (`gcloud compute disks list`,
  nom `pvc-...`), sur minikube un dossier dans la machine minikube.

Les messages restent quand : le pod leader est supprimé ou redémarre, on fait un `helm upgrade`
ou un `helm rollback`, un nœud est remplacé, ou on fait un `helm uninstall` (le PVC est gardé).

Les messages sont perdus si : on supprime le PVC, ou on détruit le cluster.

Les followers n'ont pas de volume : quand ils redémarrent, ils recopient tout depuis le leader.

## 5. Différences entre environnements

| | dev | staging | prod |
|---|---|---|---|
| Pods frontend / leader / followers | 1 / 1 / 1 | 2 / 1 / 2 | 3 / 1 / 2 |
| Ressources | réduites | par défaut | plus grandes |
| Taille du volume | 1Gi | 1Gi | 2Gi |
| Port du frontend | 8080 | 8081 | 8082 |

Le détail est dans le README (partie 7.3).

## 6. Limites

C'est un projet d'école, pas une vraie production : Redis sans mot de passe, un seul leader, pas
de HTTPS, pas de sauvegarde automatique. Voir la partie 10 du README.
