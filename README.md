# Livre d'or Cloud : GKE + Terraform + Helm

Projet d'équipe (5 étudiants). Ce README explique ce qu'on a construit et comment tout refaire
de zéro : créer le cluster, déployer les 3 environnements (sur le cloud et en local) et faire les
opérations courantes.

Dépôt : https://github.com/ahmedjer/livre-or-cloud

Autres documents :

- [docs/architecture.md](docs/architecture.md) : schémas et liste des objets
- [docs/runbooks.md](docs/runbooks.md) : les procédures d'exploitation
- [docs/decisions.md](docs/decisions.md) : nos choix techniques et pourquoi
- [docs/evidence/](docs/evidence/) : les sorties de nos tests

## Sommaire

0. [Où on en est](#0-où-on-en-est)
1. [Présentation](#1-présentation)
2. [Architecture](#2-architecture)
3. [Organisation du dépôt](#3-organisation-du-dépôt)
4. [Prérequis](#4-prérequis)
5. [Tout déployer de zéro](#5-tout-déployer-de-zéro)
6. [Exploitation](#6-exploitation)
7. [Référence Terraform et Helm](#7-référence-terraform-et-helm)
8. [Nos choix techniques](#8-nos-choix-techniques)
9. [En cas de problème](#9-en-cas-de-problème)
10. [Limites](#10-limites)
11. [Démonstration](#11-démonstration)

## 0. Où on en est

| Partie | État |
|---|---|
| Manifestes `k8s/` sur minikube | testé |
| Persistance Redis (on supprime le pod, les messages restent) | testé sur minikube et sur GKE |
| 3 releases Helm sur minikube | testé (chart 0.1.0) |
| `helm upgrade` et `helm rollback` | testé sur minikube (chart 0.1.0) |
| Terraform : `apply`, `plan` (No changes), `destroy` | testé sur GKE le 02/11 |
| 3 releases Helm sur GKE | testé le 02/11 (chart 0.1.1, installées directement en LoadBalancer) |
| Sur GKE : test en ClusterIP + port-forward, puis passage en LoadBalancer | pas encore fait |
| Chart 0.2.0 (version actuelle) | `helm lint` OK, pas encore redéployé sur minikube ni sur GKE |

Dans la version 0.2.0 on a changé les noms des objets : ils sont maintenant générés par
`_helpers.tpl` (par exemple `stack-prod-guestbook-redis-leader` au lieu de `redis-leader`). Les
fichiers de `docs/evidence/` ont été faits avant, donc on y voit encore les anciens noms.

## 1. Présentation

Cloud Hôtels veut un livre d'or : les clients laissent un message à la fin de leur séjour et les
messages s'affichent dans le hall. Le premier prototype perdait tous les messages quand il
redémarrait.

On utilise l'application d'exemple Guestbook de Kubernetes :

- un **frontend** PHP (le site web) ;
- un **Redis leader** qui reçoit les écritures ;
- des **Redis followers**, des copies du leader qui servent à lire les messages.

Ce qu'on a ajouté : un volume persistant pour Redis (les messages ne sont plus perdus), la
configuration dans des ConfigMaps, un chart Helm unique pour 3 environnements (dev, staging,
prod) et un cluster GKE créé avec Terraform.

Ce qui est automatisé :

- création et suppression du cluster GKE (Terraform) ;
- installation, mise à jour et retour arrière de l'application (Helm).

Ce qui reste manuel :

- lancer la session de lab et remplir `terraform.tfvars` ;
- se connecter avec `gcloud` ;
- lancer `minikube tunnel` ou `kubectl port-forward` pour accéder au site ;
- les sauvegardes de Redis et la suppression des volumes à la fin.

Le fichier `.github/workflows/publish-images.yml` copie juste les images vers GitHub. Il n'est
pas utilisé pour le déploiement.

## 2. Architecture

```
                 Dépôt Git : terraform/  k8s/  helm/guestbook/  docs/
                          |                         |
   CLOUD                  v                         v                LOCAL
   terraform apply -> cluster GKE              minikube (Docker Desktop)
   "autopilot-cluster-1"                             |
   gcloud get-credentials -> kubectl           kubectl (contexte minikube)
            |                                        |
            +-------- le MÊME chart helm/guestbook --+
                namespace dev     : release stack-dev     (values-dev.yaml)
                namespace staging : release stack-staging (values-staging.yaml)
                namespace prod    : release stack-prod    (values-prod.yaml)
```

Dans chaque namespace :

```
  navigateur -> Service frontend -> pods frontend (PHP)
                                      |               |
                                 écritures         lectures
                                      v               v
                       Service redis-leader     Service redis-follower
                                      v               v
                          pod redis-leader  <--  pods redis-follower
                          (1 seul, Recreate)     (copient le leader)
                                      |
                                      v
                          volume persistant (PVC) monté sur /data
```

- **Terraform crée le cluster, Helm installe l'application.** Terraform ne déploie rien dans le
  cluster et Helm ne crée rien dans GCP.
- Les messages sont dans Redis, enregistrés dans le fichier `/data/appendonly.aof` du leader, sur
  le volume persistant. Il y a un volume par environnement.
- Redis n'est jamais accessible de l'extérieur. Seul le Service `frontend` peut l'être.

Plus de détails : [docs/architecture.md](docs/architecture.md).

## 3. Organisation du dépôt

```
livre-or-cloud/
├── README.md                     ce document
├── .gitignore                    state, tfvars, kubeconfig, identifiants...
├── docs/
│   ├── architecture.md           schémas, objets, où sont les données
│   ├── runbooks.md               procédures d'exploitation (R1 à R12)
│   ├── decisions.md              nos choix techniques
│   └── evidence/                 sorties de nos tests
├── terraform/
│   ├── versions.tf               versions de Terraform et des providers
│   ├── variables.tf              les variables
│   ├── main.tf                   appel du module GKE
│   ├── outputs.tf                ce qu'on affiche après apply
│   ├── terraform.tfvars.example  modèle (le vrai terraform.tfvars n'est pas dans Git)
│   └── .terraform.lock.hcl       versions exactes des providers
├── k8s/                          manifestes Kubernetes "bruts" (première étape)
└── helm/guestbook/               le chart Helm
    ├── Chart.yaml                nom et version du chart
    ├── values.yaml               valeurs par défaut (toutes commentées)
    ├── values-dev.yaml           ce qui change pour dev
    ├── values-staging.yaml       ce qui change pour staging
    ├── values-prod.yaml          ce qui change pour prod
    ├── values-mac.yaml           en plus, seulement sur un Mac à puce Apple (voir 5.1)
    ├── charts/                   vide (pas de dépendances)
    └── templates/
        ├── _helpers.tpl          fonctions pour les noms et les labels
        ├── NOTES.txt             message affiché après l'installation
        └── ...                   un fichier par objet Kubernetes (9 fichiers)
```

Le dossier `k8s/` a servi à écrire et tester les objets sur minikube avant de faire le chart.
Le chart Helm a été fait à partir de ces fichiers.

## 4. Prérequis

### Outils

| Outil | Version qu'on a utilisée |
|---|---|
| Git | 2.x |
| Terraform | 1.16.6 (il faut au moins 1.3) |
| gcloud (Google Cloud CLI) | récente |
| gke-gcloud-auth-plugin | récente |
| kubectl | 1.30 ou plus |
| Helm | 4.3.1 (Helm 3 marche aussi) |
| Docker Desktop | 29.9.2 |
| minikube | 1.37.0 |

Le plus simple pour la partie cloud est d'utiliser **Cloud Shell** (dans la console du lab) :
gcloud, kubectl, Helm et Terraform y sont déjà installés.

Le plugin `gke-gcloud-auth-plugin` permet à kubectl de s'authentifier sur GKE. Pour l'installer
et vérifier :

```bash
gcloud components install gke-gcloud-auth-plugin
# si gcloud a été installé avec apt :
#   sudo apt-get install google-cloud-cli-gke-gcloud-auth-plugin
gke-gcloud-auth-plugin --version
```

### Comptes

- Cloud : le compte étudiant donné par le lab Google Skills
  (https://www.skills.google/paths/11/course_templates/2/labs/619578). Jamais un compte perso.
- GitHub : accès au dépôt.
- Local : Docker Desktop. `minikube tunnel` peut demander le mot de passe administrateur.

### Contraintes du lab

- **Le temps est limité** : tout est supprimé à la fin de la session. Le `terraform apply` prend
  environ 10 minutes et le `destroy` autant. Il faut lancer `terraform apply` dès le début.
- **Le projet change à chaque session** : on met le `project_id` et la `region` du lab dans
  `terraform/terraform.tfvars`, jamais dans le code.
- Le 02/11, le premier `apply` a échoué parce qu'il n'y avait plus assez de ressources dans
  `us-central1`. On a relancé et ça a marché.

### Windows / PowerShell

Les commandes sont écrites pour bash (Cloud Shell, Linux, Mac). Sous PowerShell : remplacer le
`\` en fin de ligne par un accent grave `` ` ``, et utiliser `gcloud.cmd` si `gcloud` est bloqué.

## 5. Tout déployer de zéro

On lance toutes les commandes depuis la racine du dépôt :

```bash
git clone https://github.com/ahmedjer/livre-or-cloud.git
cd livre-or-cloud
```

### 5.1 En local avec minikube

1) Démarrer minikube (Docker Desktop doit être lancé) :

```bash
minikube start --driver=docker
kubectl config use-context minikube
kubectl get nodes            # minikube doit être Ready
kubectl get storageclass     # on doit voir "standard (default)"
```

2) Vérifier le chart :

```bash
helm lint helm/guestbook -f helm/guestbook/values-dev.yaml
helm lint helm/guestbook -f helm/guestbook/values-staging.yaml
helm lint helm/guestbook -f helm/guestbook/values-prod.yaml
# résultat attendu : "0 chart(s) failed"
```

3) Installer les 3 environnements. `--create-namespace` crée le namespace s'il n'existe pas.

```bash
kubectl config current-context      # doit afficher minikube

helm install stack-dev helm/guestbook -n dev --create-namespace \
  -f helm/guestbook/values-dev.yaml --wait

helm install stack-staging helm/guestbook -n staging --create-namespace \
  -f helm/guestbook/values-staging.yaml --wait

helm install stack-prod helm/guestbook -n prod --create-namespace \
  -f helm/guestbook/values-prod.yaml --wait

helm list -A                        # les 3 releases en "deployed"
kubectl get deploy,svc,pvc -n prod  # les deployments prêts, le PVC en "Bound"
```

**Sur un Mac à puce Apple (M1, M2...)**, les images du frontend et du follower de Google ne
sont faites que pour les puces Intel/AMD (erreur `exec format error`). Il faut :

- une fois après chaque démarrage de Docker Desktop, installer l'émulateur Intel :
  `docker run --privileged --rm tonistiigi/binfmt --install amd64` (ça suffit pour le frontend) ;
- ajouter `-f helm/guestbook/values-mac.yaml` à chaque commande `helm install` / `helm upgrade`,
  par exemple :

  ```bash
  helm install stack-dev helm/guestbook -n dev --create-namespace \
    -f helm/guestbook/values-dev.yaml -f helm/guestbook/values-mac.yaml --wait
  ```

  Redis plante quand il est émulé (`Segmentation fault`), donc ce fichier remplace l'image du
  follower par l'image Redis officielle, avec la même commande. Sur GKE et sur un PC Windows, on
  ne l'utilise pas.

4) Accéder au site. Dans un **autre terminal**, lancer et laisser tourner :

```bash
minikube tunnel
```

Puis ouvrir dans le navigateur :

- dev : http://127.0.0.1:8080
- staging : http://127.0.0.1:8081
- prod : http://127.0.0.1:8082

Chaque environnement a son port, sinon les 3 se battraient pour le même port sur 127.0.0.1.
Un message écrit en dev n'apparaît pas en prod : chaque environnement a son propre Redis.

### 5.2 Sur le cloud avec GKE

1) Démarrer le lab et ouvrir Cloud Shell. Vérifier le projet :

```bash
gcloud config set project <PROJECT_ID_DU_LAB>
gcloud config get-value project
```

2) Créer le fichier de variables :

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# ouvrir terraform/terraform.tfvars et mettre le project_id et la region du lab
```

3) Créer le cluster :

```bash
terraform -chdir=terraform init       # télécharge le module et les providers
terraform -chdir=terraform validate   # "Success! The configuration is valid."
terraform -chdir=terraform plan       # 7 ressources à créer
terraform -chdir=terraform apply      # taper "yes", environ 10 minutes
terraform -chdir=terraform plan       # doit afficher "No changes"
terraform -chdir=terraform output     # nom du cluster, région, commande de connexion...
```

Si Terraform dit que l'API Kubernetes Engine n'est pas activée :
`gcloud services enable container.googleapis.com` puis relancer `apply`.

4) Se connecter au cluster :

```bash
gke-gcloud-auth-plugin --version
gcloud container clusters get-credentials autopilot-cluster-1 \
  --location <REGION> --project <PROJECT_ID>
# (c'est la commande donnée par : terraform -chdir=terraform output gke_connection_command)

kubectl config current-context   # gke_<projet>_<region>_autopilot-cluster-1
kubectl cluster-info
kubectl get namespaces
```

Pour passer de GKE à minikube (ou l'inverse) : `kubectl config get-contexts` puis
`kubectl config use-context <nom>`. **Toujours vérifier le contexte avant une commande Helm.**

5) Installer dev en ClusterIP pour tester sans ouvrir sur Internet :

```bash
helm install stack-dev helm/guestbook -n dev --create-namespace \
  -f helm/guestbook/values-dev.yaml \
  --set frontend.service.type=ClusterIP --wait --timeout 15m

kubectl get deploy,svc,pvc -n dev    # svc/frontend en ClusterIP, PVC en Bound
kubectl port-forward svc/frontend 18080:8080 -n dev
```

Ouvrir http://127.0.0.1:18080 (dans Cloud Shell : bouton *Web Preview*, changer le port en
18080) et écrire quelques messages. Arrêter avec `Ctrl+C`.

Au début, les pods peuvent rester quelques minutes en `Pending` : Autopilot crée les machines au
moment où on en a besoin. C'est normal.

6) Ouvrir sur Internet (LoadBalancer). On relance la commande sans le `--set`, donc on revient à
la valeur du fichier `values-dev.yaml` qui est `LoadBalancer` :

```bash
helm upgrade stack-dev helm/guestbook -n dev \
  -f helm/guestbook/values-dev.yaml --wait --timeout 15m

kubectl get svc frontend -n dev -w   # attendre l'EXTERNAL-IP puis Ctrl+C
```

Ouvrir `http://<EXTERNAL-IP>:8080` : les messages de l'étape 5 sont toujours là.

7) Installer staging et prod :

```bash
helm install stack-staging helm/guestbook -n staging --create-namespace \
  -f helm/guestbook/values-staging.yaml --wait --timeout 15m

helm install stack-prod helm/guestbook -n prod --create-namespace \
  -f helm/guestbook/values-prod.yaml --wait --timeout 15m

helm list -A                 # les 3 releases en "deployed"
kubectl get svc frontend -A  # une IP publique par environnement
```

8) À la fin de la session : voir le runbook R10 (désinstaller puis `terraform destroy`).

### 5.3 Tester les manifestes k8s/ (optionnel)

Les fichiers de `k8s/` sont la version "sans Helm". Pour les tester, on utilise un namespace à
part, sinon ils entrent en conflit avec les objets créés par Helm (mêmes noms de Services).

```bash
kubectl create namespace k8s-test
for f in k8s/*.yaml; do
  [ "$f" = k8s/namespaces.yaml ] || kubectl apply -n k8s-test -f "$f"
done
kubectl get all,cm,pvc -n k8s-test
kubectl delete namespace k8s-test
```

On ne passe pas `namespaces.yaml` parce qu'il crée dev, staging et prod, qui sont gérés par Helm.

### 5.4 Mettre à jour un minikube installé avec l'ancien chart (0.1.x)

Les noms des objets ont changé en 0.2.0. Un simple `helm upgrade` créerait un nouveau volume
vide. Sur minikube on n'a que des données de test, donc le plus simple est de tout réinstaller :

```bash
kubectl config current-context    # minikube
helm uninstall stack-dev -n dev
helm uninstall stack-staging -n staging
helm uninstall stack-prod -n prod
for e in dev staging prod; do kubectl delete pvc redis-leader-pvc -n $e --ignore-not-found; done
# les anciens objets créés avec kubectl apply dans dev :
kubectl delete deploy,svc,cm -n dev -l app.kubernetes.io/instance=guestbook --ignore-not-found
```

Puis refaire l'étape 3 du 5.1.

## 6. Exploitation

Toutes les procédures sont dans [docs/runbooks.md](docs/runbooks.md) :

| Besoin | Runbook |
|---|---|
| Vérifier qu'un environnement va bien | R1 |
| Déployer une nouvelle version | R2 |
| Revenir à la version d'avant | R3 |
| Changer la configuration d'un environnement | R4 |
| Plus de pods ou plus de ressources | R5 |
| Agrandir le volume | R6 |
| Vérifier que les données sont bien sauvegardées | R7 |
| Passer le frontend de ClusterIP à LoadBalancer (et l'inverse) | R8 |
| Se reconnecter depuis un autre PC | R9 |
| Tout désinstaller et détruire le cluster | R10 |
| Chercher une panne | R11 |
| Faire une sauvegarde de Redis | R12 |

Trois règles :

1. vérifier `kubectl config current-context` avant chaque commande ;
2. on modifie l'application **uniquement avec Helm** (pas de `kubectl apply` ou `kubectl edit`
   sur les objets du chart) ;
3. un changement qui doit rester se fait dans un fichier `values-<ENV>.yaml` et on le commit.

## 7. Référence Terraform et Helm

### 7.1 Terraform

Module utilisé : `terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-public-cluster`,
version `~> 46.0` (la 46.0.0 est installée). Dans `main.tf` on ne passe que les arguments
demandés : `source`, `version`, `project_id`, `name`, `region`, `network`, `subnetwork`,
`ip_range_pods`, `ip_range_services`, `release_channel`, `deletion_protection`.

**Ce que Terraform crée** (vu avec `terraform state list` après le apply) :

| Ressource | À quoi ça sert |
|---|---|
| `google_container_cluster.primary` | le cluster GKE Autopilot `autopilot-cluster-1` |
| `google_service_account.cluster_service_account` | le compte de service utilisé par les nœuds |
| `google_project_iam_member` (3 fois) | les droits de ce compte : `container.defaultNodeServiceAccount`, `monitoring.metricWriter`, `stackdriver.resourceMetadata.writer` |
| `random_string.cluster_service_account_suffix` | un suffixe aléatoire pour le nom du compte de service |
| `random_shuffle.available_zones` | le choix des zones dans la région |

Pas de réseau ni de règle de firewall créés : on utilise le réseau `default` qui existe déjà.

**Variables** :

| Nom | Description | Type | Par défaut | Obligatoire |
|---|---|---|---|---|
| `project_id` | ID du projet du lab | string | - | oui |
| `region` | région du lab, par exemple `us-central1` (vérifiée) | string | - | oui |
| `cluster_name` | nom du cluster | string | `autopilot-cluster-1` | non |
| `network` | réseau VPC | string | `default` | non |
| `subnetwork` | sous-réseau | string | `default` | non |
| `ip_range_pods` | plage IP des pods (null = automatique) | string | `null` | non |
| `ip_range_services` | plage IP des services (null = automatique) | string | `null` | non |
| `release_channel` | canal de mise à jour (RAPID, REGULAR ou STABLE) | string | `REGULAR` | non |
| `deletion_protection` | protection contre la suppression | bool | `false` | non |

**Providers** (dans `versions.tf`) :

| Provider | Contrainte | Version installée |
|---|---|---|
| hashicorp/google | `~> 8.0` | 8.9.0 |
| hashicorp/google-beta | `~> 8.0` | 8.9.0 |
| hashicorp/kubernetes | `~> 2.0` | 2.38.0 |
| hashicorp/random | `~> 3.0` | 3.9.1 |

On a vérifié que ces versions sont compatibles avec celles demandées par le module
(google et google-beta entre 7.28 et 9, kubernetes entre 2.10 et 4).

**Outputs** :

| Output | Contenu | Exemple |
|---|---|---|
| `cluster_name` | nom du cluster | `autopilot-cluster-1` |
| `cluster_location` | région | `us-central1` |
| `project_id` | projet | `qwiklabs-gcp-xx-xxxx` |
| `cluster_id` | identifiant complet | `projects/qwiklabs-gcp-xx-xxxx/locations/us-central1/clusters/autopilot-cluster-1` |
| `cluster_endpoint` | adresse de l'API (cachée) | `<sensitive>`, à lire avec `terraform output -raw cluster_endpoint` |
| `kubernetes_version` | version de Kubernetes | `1.36.4-gke.2046003` |
| `release_channel` | canal appliqué | `REGULAR` |
| `gke_connection_command` | commande pour connecter kubectl | `gcloud container clusters get-credentials autopilot-cluster-1 --location us-central1 --project qwiklabs-gcp-xx-xxxx` |

Commandes : `terraform -chdir=terraform init`, `plan`, `apply`, `output`, `destroy`.

Le state Terraform est en local (voir decisions.md, D10). Après un `apply`, `plan` affiche bien
`No changes` (testé le 02/11).

### 7.2 Objets créés par le chart

Pour chaque environnement : 3 Deployments, 3 Services, 2 ConfigMaps et 1 PVC. La liste avec les
noms est dans [docs/architecture.md](docs/architecture.md#2-les-objets-dune-release).

### 7.3 Valeurs Helm

Chaque valeur est expliquée dans [values.yaml](helm/guestbook/values.yaml). Dans le tableau, "-"
veut dire qu'on garde la valeur par défaut. Pour les ressources on note
`requests cpu/mémoire puis limits cpu/mémoire`.

| Valeur | Rôle | Défaut | dev | staging | prod |
|---|---|---|---|---|---|
| `commonLabels.environment` | label environment | dev | dev | staging | prod |
| `commonLabels.team` | label team | platform | - | - | - |
| `frontend.replicaCount` | nombre de pods frontend | 1 | 1 | 2 | 3 |
| `frontend.image.repository` / `tag` | image du frontend | gb-frontend / v5 | - | - | - |
| `frontend.env.GET_HOSTS_FROM` | comment le frontend trouve Redis | dns | - | - | - |
| `frontend.service.name` | nom du Service | frontend | - | - | - |
| `frontend.service.type` | type du Service | LoadBalancer | LoadBalancer | LoadBalancer | LoadBalancer |
| `frontend.service.port` | port du Service | 8080 | 8080 | 8081 | 8082 |
| `frontend.resources` | CPU / mémoire | 100m/128Mi puis 250m/256Mi | 50m/64Mi puis 200m/128Mi | - | 150m/192Mi puis 300m/384Mi |
| `frontend.readinessProbe` | délai, période, timeout, échecs | 5s, 5s, 3s, 3 | - | - | - |
| `frontend.livenessProbe` | délai, période, timeout, échecs | 15s, 10s, 3s, 3 | - | - | - |
| `redisLeader.replicaCount` | toujours 1 | 1 | - | - | - |
| `redisLeader.image.repository` / `tag` | image Redis | redis / 6.0.5 | - | - | - |
| `redisLeader.service.name` / `port` | Service du leader (nom à ne pas changer) | redis-leader / 6379 | - | - | - |
| `redisLeader.persistence.size` | taille du volume | 1Gi | 1Gi | 1Gi | 2Gi |
| `redisLeader.persistence.accessMode` | mode d'accès du volume | ReadWriteOnce | - | - | - |
| `redisLeader.persistence.storageClass` | vide = classe par défaut | "" | - | - | - |
| `redisLeader.redisConfig` | contenu de redis.conf | dir /data, appendonly yes... | - | - | - |
| `redisLeader.resources` | CPU / mémoire | 100m/128Mi puis 250m/256Mi | 50m/64Mi puis 200m/128Mi | - | 200m/256Mi puis 500m/512Mi |
| `redisLeader.readinessProbe` / `livenessProbe` | probes | 5s, 5s, 2s, 3 / 15s, 10s, 2s, 3 | - | - | - |
| `redisFollower.replicaCount` | nombre de followers | 1 | 1 | 2 | 2 |
| `redisFollower.image.repository` / `tag` | image follower | gb-redis-follower / v2 | - | - | - |
| `redisFollower.service.name` / `port` | Service des followers (nom à ne pas changer) | redis-follower / 6379 | - | - | - |
| `redisFollower.resources` | CPU / mémoire | 100m/128Mi puis 250m/256Mi | 50m/64Mi puis 200m/128Mi | - | 150m/192Mi puis 300m/384Mi |
| `redisFollower.readinessProbe` / `livenessProbe` | probes | 5s, 5s, 2s, 3 / 15s, 10s, 2s, 3 | - | - | - |

Il y a aussi `nameOverride`, `fullnameOverride` et `pullPolicy` (toujours `IfNotPresent`), qu'on
ne change pas.

Pour voir les valeurs utilisées par une release : `helm get values stack-<ENV> -n <ENV> --all`.

## 8. Nos choix techniques

Les explications complètes sont dans [docs/decisions.md](docs/decisions.md). En résumé :

- **Terraform pour le cluster, Helm pour l'application** : ce sont deux choses qui ne changent pas
  au même rythme.
- **Recreate pour le Redis leader** : son volume ne peut être utilisé que par un seul pod à la fois.
- **Redis en mode AOF** avec écriture sur disque après chaque message : on ne perd rien.
- **Probes** : `httpGet /` pour le frontend, `redis-cli ping` pour Redis.
- **Ressources** plus petites en dev et plus grandes en prod.
- **Noms des Services Redis fixes** (`redis-leader`, `redis-follower`) parce que les images les
  utilisent en dur.
- **StorageClass vide** : on n'écrit pas `storageClassName`, donc c'est la classe par défaut.
- **`--set frontend.service.type=ClusterIP`** pour la phase de test sur GKE.
- **PVC gardé** quand on fait `helm uninstall`.
- **State Terraform en local** parce que le projet du lab est temporaire.

## 9. En cas de problème

Les commandes de diagnostic sont dans le runbook R11. Les problèmes qu'on a déjà eus :

| Problème | Cause | Solution |
|---|---|---|
| `terraform apply` échoue : pas assez de ressources dans la région | GKE manquait de place dans le lab | relancer `terraform apply` |
| `terraform init` : "not enough space on the disk" | disque plein | libérer de la place et relancer |
| `gcloud.ps1 cannot be loaded` (PowerShell) | sécurité de PowerShell | utiliser `gcloud.cmd` |
| `kubectl` : "connection refused" sur 127.0.0.1 | Docker Desktop ou minikube arrêté | démarrer Docker puis `minikube start` |
| `helm install` : "resource already exists" ou "field is immutable" | des objets avaient été créés avant avec `kubectl apply` | voir 5.3 et 5.4 |
| PVC en `Pending` | pas de StorageClass par défaut | `kubectl get storageclass`, `kubectl describe pvc -n <ENV>` |
| Pods en `Pending` quelques minutes sur GKE | Autopilot crée les machines | attendre, `kubectl get events -n <ENV>` |
| `EXTERNAL-IP` reste en `<pending>` en local | `minikube tunnel` pas lancé | le lancer dans un autre terminal |
| Mac : `exec format error` dans `kubectl logs` | images faites pour les puces Intel/AMD | installer l'émulateur (voir 5.1) |
| Mac : follower en `CrashLoopBackOff`, `Segmentation fault` dans les logs | Redis plante quand il est émulé | ajouter `-f helm/guestbook/values-mac.yaml` (voir 5.1) |

## 10. Limites

Ce projet n'est pas prêt pour une vraie production :

- Redis n'a pas de mot de passe. Il faudrait en mettre un (dans un Secret) et limiter qui peut
  parler à Redis.
- Il n'y a qu'un seul Redis leader : quand il redémarre, on ne peut pas écrire pendant quelques
  secondes. Il faudrait une solution Redis haute disponibilité.
- Pas de HTTPS : le site est en HTTP simple.
- Pas de sauvegarde automatique. Le volume persistant protège contre un redémarrage, pas contre une
  suppression. La restauration n'a pas été testée.
- Les images sont des images d'exemple de Google et Redis 6.0.5 est une vieille version.
- Pas de monitoring ni d'alertes.

Ce qu'on n'a pas encore fait : le test ClusterIP puis LoadBalancer sur GKE, et le déploiement du
chart 0.2.0 (voir partie 0).

## 11. Démonstration

| Étape | Ce qu'on fait |
|---|---|
| 1 | `terraform -chdir=terraform plan` affiche No changes, puis `terraform -chdir=terraform output` |
| 2 | `gke-gcloud-auth-plugin --version`, `get-credentials`, `kubectl cluster-info` (5.2 étape 4) |
| 3 | `stack-dev` en ClusterIP, `port-forward`, on écrit des messages (5.2 étape 5) |
| 4 | `helm upgrade stack-dev`, le Service passe en LoadBalancer (5.2 étape 6) |
| 5 | installation de staging et prod, `helm list -A` (5.2 étape 7) |
| 6 | on supprime le pod redis-leader de prod, les messages restent (runbook R7) |
| 7 | on passe le chart en 0.2.1, `helm upgrade`, `helm history` (runbook R2) |
| 8 | `kubectl describe deploy stack-prod-guestbook-redis-leader -n prod` : probes, ressources, labels, Recreate |
| 9 | même chose en local avec minikube et `minikube tunnel` (5.1) |
| 10 | `helm uninstall` puis `terraform destroy` (runbook R10) |
