
# Runbooks d'exploitation — Cloud Guestbook

## 1. Objectif

Ce document décrit les opérations courantes sur Cloud Guestbook :

- Vérifier l'état des environnements.
- Déployer une release Helm.
- Modifier le nombre de réplicas.
- Mettre à jour une release et revenir en arrière.
- Vérifier la persistance et la réplication Redis.
- Diagnostiquer les incidents.
- Basculer entre Minikube et GKE.
- Préparer la désinstallation et le nettoyage.

Les procédures locales ont été testées sur Minikube.
Les procédures GKE sont préparées mais restent à valider en laboratoire.

Toutes les commandes PowerShell sont exécutées depuis la racine
du dépôt `livre-or-cloud`, sauf indication contraire.

## 2. Contrôles préalables

Avant toute opération Kubernetes ou Helm, identifier le cluster
actif pour éviter de modifier le mauvais environnement.

```powershell
kubectl config current-context
kubectl config get-contexts
kubectl cluster-info
helm list -A
```

Pour travailler sur Minikube :

```powershell
kubectl config use-context minikube
```

Ne jamais supposer que le contexte actif est le bon.

## 3. Vérifier l'état des environnements

Utiliser ce runbook après un déploiement, une mise à jour
ou lorsqu'une anomalie est signalée.

```powershell
helm list -A

kubectl get deployments -n dev
kubectl get deployments -n staging
kubectl get deployments -n prod

kubectl get pods -A
kubectl get pvc -A
```

Réplicas attendus en configuration nominale :

| Composant | dev | staging | prod |
|---|---:|---:|---:|
| Frontend | 1 | 2 | 3 |
| Redis Leader | 1 | 1 | 1 |
| Redis Followers | 1 | 2 | 2 |

Résultats attendus :

- Releases Helm au statut `deployed`.
- Tous les réplicas attendus au statut Ready.
- PVC au statut `Bound`.
- Services Redis et frontend présents.

Pour vérifier la connectivité des Services :

```powershell
kubectl get svc,endpoints -n dev
kubectl get svc,endpoints -n staging
kubectl get svc,endpoints -n prod
```

Les Services applicatifs doivent posséder des endpoints.

## 4. Installer une release Helm

Ce runbook s'applique à un namespace vierge.

Vérifier d'abord le contexte et valider le chart :

```powershell
kubectl config current-context

helm lint .\helm\guestbook `
  -f .\helm\guestbook\values-staging.yaml
```

Exemple d'installation de staging sur un cluster neuf :

```powershell
helm install stack-staging .\helm\guestbook `
  --namespace staging `
  --create-namespace `
  -f .\helm\guestbook\values-staging.yaml `
  --wait `
  --timeout 10m
```

Contrôler :

```powershell
helm status stack-staging -n staging
kubectl get pods,svc,pvc -n staging
```

Ne pas réinstaller une release qui existe déjà.

Cas particulier : le namespace dev sur le Minikube historique
a été migré depuis des manifestes classiques avec Helm
`--take-ownership`. Ne pas rejouer cette migration sur un
cluster neuf.

## 5. Modifier le nombre de réplicas

Utiliser ce runbook pour augmenter ou diminuer la capacité
du frontend.

Exemple : passer staging de 2 à 3 frontends.

```powershell
helm upgrade stack-staging .\helm\guestbook `
  --namespace staging `
  -f .\helm\guestbook\values-staging.yaml `
  --set frontend.replicaCount=3 `
  --wait `
  --timeout 10m
```

Vérifier :

```powershell
kubectl get deployment frontend -n staging
kubectl get pods -n staging
helm history stack-staging -n staging
```

Résultat attendu : `frontend` affiche 3/3 réplicas Ready.

Pour rendre ce changement permanent, modifier également
`values-staging.yaml`, puis versionner le fichier.

Ne pas modifier directement le nombre de réplicas avec
`kubectl scale` lorsqu'il est géré par Helm.

## 6. Effectuer un rollback Helm

Utiliser ce runbook après une mise à jour problématique.

Consulter l'historique :

```powershell
helm history stack-staging -n staging
```

Identifier la révision stable à restaurer.

Exemple testé dans le projet : retour à la révision 1.

```powershell
helm rollback stack-staging 1 `
  --namespace staging `
  --wait `
  --timeout 10m
```

Vérifier :

```powershell
helm history stack-staging -n staging
kubectl get deployments -n staging
kubectl get pods -n staging
```

Le rollback crée une nouvelle révision Helm.
Il ne supprime pas les anciennes révisions de l'historique.

Les messages Redis doivent rester disponibles après le rollback.

## 7. Vérifier Redis

### 7.1 Disponibilité du leader

```powershell
kubectl exec -n dev deployment/redis-leader -- redis-cli PING
```

Résultat attendu : `PONG`.

### 7.2 Réplication

```powershell
kubectl exec -n dev deployment/redis-follower -- `
  redis-cli INFO replication
```

Vérifier :

- `role:slave` (terminologie Redis 6).
- `master_host:redis-leader`.
- `master_link_status:up`.
- `master_sync_in_progress:0`.

### 7.3 Persistance

Vérifier une clé créée précédemment :

```powershell
kubectl exec -n dev deployment/redis-leader -- `
  redis-cli GET persistence_test
```

Dans notre environnement de test, la valeur attendue est `hello`.

Vérifier le PVC :

```powershell
kubectl get pvc redis-leader-pvc -n dev
```

La ressource doit rester `Bound`.

### 7.4 Tester un redémarrage

Cette opération provoque une interruption temporaire du leader.
Ne pas l'exécuter pendant une période d'utilisation sensible.

Avant le test, vérifier que la sauvegarde des données existe.

```powershell
kubectl get pods -n dev `
  -l app.kubernetes.io/component=redis-leader
```

Le Pod peut ensuite être supprimé pour valider sa recréation
automatique par Kubernetes. Après le redémarrage, contrôler
la valeur Redis et le PVC d'origine.

## 8. Sauvegarder Redis

La persistance sur PVC protège les données contre un redémarrage
de Pod, mais ne remplace pas une sauvegarde indépendante.

Créer une sauvegarde Redis :

```powershell
kubectl exec -n dev deployment/redis-leader -- redis-cli SAVE

$redisPod = kubectl get pods -n dev `
  -l app.kubernetes.io/component=redis-leader `
  -o jsonpath='{.items[0].metadata.name}'

New-Item -ItemType Directory -Force `
  -Path ..\guestbook-backup | Out-Null

kubectl cp "dev/${redisPod}:/data/dump.rdb" `
  "..\guestbook-backup\dev-redis-dump.rdb"

kubectl cp "dev/${redisPod}:/data/appendonly.aof" `
  "..\guestbook-backup\dev-redis-appendonly.aof"
```

Vérifier les fichiers obtenus :

```powershell
Get-ChildItem ..\guestbook-backup
```

Ne pas versionner les sauvegardes contenant des données.

La procédure de restauration doit être testée séparément
avant toute utilisation sur des données importantes.

## 9. Diagnostiquer un incident

### 9.1 Identifier les ressources en anomalie

```powershell
kubectl get pods -n staging
kubectl get events -n staging --sort-by=.lastTimestamp
helm status stack-staging -n staging
```

### 9.2 Examiner un Deployment

```powershell
kubectl describe deployment frontend -n staging
kubectl describe deployment redis-leader -n staging
```

### 9.3 Consulter les journaux

```powershell
kubectl logs -n staging deployment/frontend --tail=100
kubectl logs -n staging deployment/redis-leader --tail=100
kubectl logs -n staging deployment/redis-follower --tail=100
```

### 9.4 Vérifier la configuration Helm

```powershell
helm get values stack-staging -n staging
helm history stack-staging -n staging
```

Points à contrôler :

- Image introuvable ou échec de démarrage.
- Erreur de ConfigMap.
- PVC non monté ou en attente.
- Readiness ou liveness probe en échec.
- Redis Follower déconnecté du leader.
- Service sans endpoints.

Corriger la configuration dans les sources du projet, puis
appliquer la modification avec Helm.

## 10. Accès à l'application sur Minikube

Vérifier le contexte :

```powershell
kubectl config current-context
```

Dans un terminal dédié, lancer :

```powershell
minikube tunnel
```

Consulter les Services :

```powershell
kubectl get svc -n dev
kubectl get svc -n staging
kubectl get svc -n prod
```

Ports locaux prévus :

- dev : http://127.0.0.1:8080
- staging : http://127.0.0.1:8081
- prod : http://127.0.0.1:8082

Alternative sans tunnel :

```powershell
kubectl port-forward -n dev svc/frontend 18080:8080
```

Accès : http://127.0.0.1:18080

## 11. Préparation GKE — Non encore validée

Le cluster GKE Autopilot sera créé avec Terraform.

Avant l'opération, vérifier le compte GCP autorisé, le
projet, la région et les quotas disponibles.

La connexion est prévue avec :

```powershell
gcloud.cmd container clusters get-credentials autopilot-cluster-1 `
  --location <REGION> `
  --project <PROJECT_ID>
```

Vérifier impérativement le contexte Kubernetes après connexion.

### Particularité de dev sur un nouveau cluster

Le fichier `values-dev.yaml` conserve le sélecteur historique
`guestbook` utilisé lors de l'adoption sur Minikube.

Sur un cluster GKE vierge, forcer un sélecteur correspondant
au nom de la release avec :

`--set-string selectorInstanceOverride=`

### Test initial en ClusterIP

```powershell
helm install stack-dev .\helm\guestbook `
  --namespace dev `
  --create-namespace `
  -f .\helm\guestbook\values-dev.yaml `
  --set-string selectorInstanceOverride= `
  --set frontend.service.type=ClusterIP `
  --wait `
  --timeout 10m
```

Tester ensuite :

```powershell
kubectl port-forward -n dev svc/frontend 18080:8080
```

### Ouverture en LoadBalancer

Après validation fonctionnelle :

```powershell
helm upgrade stack-dev .\helm\guestbook `
  --namespace dev `
  -f .\helm\guestbook\values-dev.yaml `
  --set-string selectorInstanceOverride= `
  --set frontend.service.type=LoadBalancer `
  --wait `
  --timeout 10m
```

Vérifier :

```powershell
kubectl get svc frontend -n dev
```

Ces commandes GKE sont préparées, mais leur exécution réelle
reste en attente d'accès au laboratoire Google Skills.

## 12. Désinstallation et nettoyage

Attention : supprimer une release Helm ou détruire un cluster
peut entraîner une perte définitive de données.

Avant toute désinstallation :

1. Vérifier le contexte Kubernetes.
2. Sauvegarder les données Redis.
3. Vérifier la politique de conservation des PVC.
4. Identifier les volumes et données à préserver.

Le chart 0.1.1 inclut l'annotation :

`helm.sh/resource-policy: keep`

Cependant, les releases installées avec la version 0.1.0
peuvent encore présenter un risque de suppression du PVC.

Ne jamais supposer qu'un PVC est automatiquement conservé
sans vérifier les manifestes de la release installée.

La procédure de destruction de GKE avec `terraform destroy`
sera exécutée uniquement durant une session de lab autorisée.

## 13. Limites opérationnelles

- Redis Leader est un point unique de défaillance.
- Le PVC ne protège pas contre toutes les pertes de données.
- La restauration complète Redis reste à valider.
- Les opérations cloud restent à démontrer.
- La sécurité Redis nécessite un durcissement avant production.
- Les volumes persistants ne doivent pas être supprimés
  pendant les tests de déploiement.
