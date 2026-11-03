# Runbooks d'exploitation

Retour au [README](../README.md).

Les commandes se lancent depuis la racine du dépôt. Dans les exemples, `<ENV>` veut dire `dev`,
`staging` ou `prod`. La release s'appelle toujours `stack-<ENV>`.

Noms des objets (exemple pour prod) :

| Objet | Nom |
|---|---|
| Deployments | `stack-prod-guestbook-frontend`, `stack-prod-guestbook-redis-leader`, `stack-prod-guestbook-redis-follower` |
| PVC | `stack-prod-guestbook-redis-leader-data` |
| Services | `frontend`, `redis-leader`, `redis-follower` |

**Avant chaque commande, on vérifie sur quel cluster on est :**

```bash
kubectl config current-context
# minikube  ou  gke_<projet>_<region>_autopilot-cluster-1
```

Pour changer : `kubectl config get-contexts` puis `kubectl config use-context <nom>`.

**On ne modifie les objets du chart qu'avec Helm.** Pas de `kubectl apply`, `kubectl edit` ou
`kubectl scale` : Helm effacerait ces changements au prochain upgrade.

La commande de mise à jour qu'on utilise partout (exemple pour staging) :

```bash
helm upgrade stack-staging helm/guestbook -n staging \
  -f helm/guestbook/values-staging.yaml --wait
```

---

## R1. Vérifier qu'un environnement va bien

**Quand :** après chaque opération, ou si quelqu'un signale un problème.

```bash
helm list -A
kubectl get deploy,pods,svc,pvc -n prod
kubectl get endpoints -n prod
```

**C'est bon si :** la release est en `deployed`, les deployments sont prêts (en prod : frontend
3/3, leader 1/1, followers 2/2), le PVC est en `Bound`, et chaque Service a des endpoints (pas
`<none>`).

## R2. Déployer une nouvelle version

**Quand :** on change l'image ou les templates du chart.

1. Faire la modification :
   - nouvelle image : changer `frontend.image.tag` (ou un autre composant) dans `values.yaml` ;
   - augmenter `version` dans `helm/guestbook/Chart.yaml` (par exemple 0.2.0 vers 0.2.1).
2. Vérifier :

   ```bash
   helm lint helm/guestbook -f helm/guestbook/values-prod.yaml
   ```

3. Déployer d'abord en dev, vérifier, puis staging, puis prod :

   ```bash
   helm upgrade stack-prod helm/guestbook -n prod \
     -f helm/guestbook/values-prod.yaml --wait
   ```

4. Vérifier :

   ```bash
   helm history stack-prod -n prod     # nouvelle révision avec la nouvelle version du chart
   kubectl get pods -n prod            # nouveaux pods en Running
   kubectl exec -n prod deploy/stack-prod-guestbook-redis-leader -- redis-cli GET guestbook
   ```

   Les messages sont toujours là.

**À savoir :** quand la version du chart change, tous les pods sont recréés (le label
`helm.sh/chart` change). Le leader s'arrête quelques secondes (Recreate) mais garde ses données.
Le frontend et les followers sont remplacés sans coupure.

## R3. Revenir à la version d'avant

**Quand :** une mise à jour pose problème.

```bash
helm history stack-prod -n prod                # trouver le numéro de la bonne révision
helm rollback stack-prod <REVISION> -n prod --wait
helm history stack-prod -n prod                # une nouvelle ligne "Rollback to <REVISION>"
```

**C'est bon si :** `helm get values stack-prod -n prod` montre l'ancienne configuration et les
messages sont toujours là (le rollback ne touche pas au PVC).

Ensuite il faut aussi corriger le fichier dans Git, sinon le prochain `helm upgrade` remettra la
mauvaise version.

## R4. Changer la configuration d'un environnement

**Quand :** on veut changer un réglage pour un seul environnement.

1. Lire le commentaire de la valeur dans `helm/guestbook/values.yaml`.
2. Ajouter ou modifier la valeur dans `helm/guestbook/values-<ENV>.yaml`, avec un commentaire.
3. Regarder le résultat sans rien installer :

   ```bash
   helm template stack-staging helm/guestbook -n staging -f helm/guestbook/values-staging.yaml
   ```

4. Appliquer avec la commande `helm upgrade` habituelle.
5. Vérifier : `helm get values stack-staging -n staging --all`.
6. Commit du fichier.

Cas particulier : si on change une variable du frontend (`frontend.env`), la ConfigMap change mais
les pods déjà lancés gardent l'ancienne valeur. Il faut les redémarrer :
`kubectl rollout restart deploy/stack-staging-guestbook-frontend -n staging`. Pareil pour
`redis.conf` avec le leader.

## R5. Plus de pods ou plus de ressources

**Quand :** il y a beaucoup de trafic, ou des pods en `OOMKilled`.

Exemple pour staging, dans `helm/guestbook/values-staging.yaml` :

```yaml
frontend:
  # 3 pods pour plus de trafic.
  replicaCount: 3
  resources:
    limits:
      # Plus de mémoire, on avait des OOMKilled.
      memory: 512Mi
```

Puis :

```bash
helm upgrade stack-staging helm/guestbook -n staging \
  -f helm/guestbook/values-staging.yaml --wait
kubectl get deploy stack-staging-guestbook-frontend -n staging    # 3/3
kubectl describe pod -n staging -l app.kubernetes.io/component=frontend | grep -A3 Limits
```

Pour un test rapide sans modifier le fichier : ajouter `--set frontend.replicaCount=3` à la
commande (ce sera annulé au prochain upgrade sans le `--set`).

Attention : `redisLeader.replicaCount` doit rester à 1.

## R6. Agrandir le volume

**Quand :** le disque de Redis se remplit.

```bash
kubectl exec -n prod deploy/stack-prod-guestbook-redis-leader -- df -h /data
```

1. Vérifier que la StorageClass permet d'agrandir :

   ```bash
   kubectl get storageclass
   # colonne ALLOWVOLUMEEXPANSION : true sur GKE (standard-rwo)
   ```

   Sur minikube ce n'est pas possible, mais la taille n'y est pas vraiment appliquée.
2. Changer `redisLeader.persistence.size` dans `values-prod.yaml` (par exemple 2Gi vers 5Gi).
3. `helm upgrade` habituel.
4. Vérifier : `kubectl get pvc -n prod` montre la nouvelle taille (ça peut prendre une minute).

On ne peut **jamais réduire** la taille d'un volume : le `helm upgrade` échouerait. On ne peut
pas non plus changer le mode d'accès ou la StorageClass d'un PVC qui existe déjà.

## R7. Vérifier que les données sont bien gardées

**Quand :** pour contrôler, ou pour le test de persistance de la démo.

```bash
kubectl get pvc -n prod                       # Bound
kubectl exec -n prod deploy/stack-prod-guestbook-redis-leader -- redis-cli CONFIG GET dir         # /data
kubectl exec -n prod deploy/stack-prod-guestbook-redis-leader -- redis-cli CONFIG GET appendonly  # yes
kubectl exec -n prod deploy/stack-prod-guestbook-redis-leader -- ls -l /data                      # appendonly.aof
kubectl exec -n prod deploy/stack-prod-guestbook-redis-follower -- redis-cli INFO replication     # master_link_status:up
```

**Où sont les données :** dans le fichier `/data/appendonly.aof` du leader, sur le PVC
`stack-prod-guestbook-redis-leader-data`. Sur GKE c'est un disque Google (on le voit avec
`gcloud compute disks list`, nom `pvc-...`). Les messages sont dans la clé Redis `guestbook`.

**Test de persistance :**

1. Écrire 3 messages sur le site de prod.
2. Supprimer le pod du leader :

   ```bash
   kubectl delete pod -n prod -l app.kubernetes.io/component=redis-leader
   ```

3. Attendre que le nouveau pod soit prêt :

   ```bash
   kubectl rollout status deploy/stack-prod-guestbook-redis-leader -n prod
   kubectl get pods -n prod
   ```

4. Recharger la page : les 3 messages sont toujours là. On peut aussi vérifier avec :

   ```bash
   kubectl exec -n prod deploy/stack-prod-guestbook-redis-leader -- redis-cli GET guestbook
   ```

Les followers se reconnectent tout seuls au nouveau leader après quelques secondes.

## R8. Passer le frontend de ClusterIP à LoadBalancer (et l'inverse)

**Quand :** sur GKE, après avoir testé avec port-forward, ou pour fermer l'accès public.

**Ouvrir (ClusterIP vers LoadBalancer) :** relancer l'upgrade habituel, sans `--set` :

```bash
helm upgrade stack-dev helm/guestbook -n dev \
  -f helm/guestbook/values-dev.yaml --wait
kubectl get svc frontend -n dev -w     # attendre l'EXTERNAL-IP, puis Ctrl+C
```

Le site est sur `http://<EXTERNAL-IP>:8080` (8081 pour staging, 8082 pour prod).

**Fermer (LoadBalancer vers ClusterIP) :**

```bash
helm upgrade stack-dev helm/guestbook -n dev \
  -f helm/guestbook/values-dev.yaml \
  --set frontend.service.type=ClusterIP --wait
kubectl get svc frontend -n dev                    # TYPE ClusterIP
kubectl port-forward svc/frontend 18080:8080 -n dev
```

Le site est alors sur http://127.0.0.1:18080 (Cloud Shell : Web Preview, port 18080).

Pour que ce soit définitif, mettre `type: ClusterIP` dans `values-dev.yaml`.

## R9. Se reconnecter depuis un autre PC

**Quand :** nouveau PC, nouveau Cloud Shell, ou kubeconfig perdu.

```bash
gcloud auth login
gcloud config set project <PROJECT_ID>
gcloud components install gke-gcloud-auth-plugin
gke-gcloud-auth-plugin --version
gcloud container clusters get-credentials autopilot-cluster-1 \
  --location <REGION> --project <PROJECT_ID>
kubectl config current-context
kubectl get namespaces
helm list -A
```

Les releases Helm sont enregistrées dans le cluster, donc on les retrouve depuis n'importe quel
PC. Il suffit d'avoir le dépôt Git pour le chart.

## R10. Tout désinstaller et détruire le cluster

**Quand :** à la fin de la session de lab.

1. Désinstaller les releases :

   ```bash
   kubectl config current-context     # bien vérifier qu'on est sur le bon cluster
   helm uninstall stack-dev -n dev
   helm uninstall stack-staging -n staging
   helm uninstall stack-prod -n prod
   helm list -A                       # plus rien
   kubectl get pvc -A                 # les PVC sont encore là (annotation keep)
   ```

2. Supprimer les PVC et les namespaces (les messages sont alors perdus) :

   ```bash
   kubectl delete pvc --all -n dev
   kubectl delete pvc --all -n staging
   kubectl delete pvc --all -n prod
   kubectl delete namespace dev staging prod
   ```

   Il faut le faire avant de détruire le cluster, sinon des disques peuvent rester dans le projet.

3. Détruire le cluster :

   ```bash
   terraform -chdir=terraform destroy        # taper "yes", 5 à 10 minutes
   terraform -chdir=terraform state list     # vide
   ```

## R11. Chercher une panne

Commandes utiles :

```bash
kubectl get pods -n <ENV>
kubectl describe pod <nom-du-pod> -n <ENV>        # regarder la partie Events en bas
kubectl logs <nom-du-pod> -n <ENV>
kubectl logs <nom-du-pod> -n <ENV> --previous     # logs avant le dernier redémarrage
kubectl get events -n <ENV> --sort-by=.lastTimestamp
helm status stack-<ENV> -n <ENV>
helm get values stack-<ENV> -n <ENV> --all
```

| Ce qu'on voit | Ce que ça peut être |
|---|---|
| pod en `Pending` | sur GKE, Autopilot crée une machine (attendre 1 ou 2 minutes) ; ou le PVC n'est pas `Bound` |
| PVC en `Pending` | pas de StorageClass par défaut (`kubectl get storageclass`) |
| `CrashLoopBackOff` | erreur dans `redis.conf`, ou pas assez de mémoire (`OOMKilled` dans `describe`) |
| pod jamais `Ready` | la readiness probe échoue (voir Events dans `describe`) |
| le site ne garde pas les messages | un Service Redis sans endpoints (`kubectl get endpoints -n <ENV>`), ou un Service renommé |
| `helm upgrade` : "field is immutable" | on a essayé de changer un selector, ou de réduire la taille du PVC |
| `helm install` : "already exists" | la release existe déjà (faire `helm upgrade`), ou des objets créés avant avec `kubectl apply` |
| `EXTERNAL-IP` en `<pending>` | en local : `minikube tunnel` n'est pas lancé ; sur GKE : attendre 1 à 3 minutes |

## R12. Faire une sauvegarde de Redis

Le PVC protège contre un redémarrage, mais pas si on supprime le PVC ou le cluster. Pour garder
une copie des messages :

```bash
POD=$(kubectl get pod -n prod -l app.kubernetes.io/component=redis-leader -o jsonpath='{.items[0].metadata.name}')
mkdir -p ../sauvegarde
kubectl cp prod/$POD:/data/appendonly.aof ../sauvegarde/prod-appendonly.aof
ls -l ../sauvegarde
```

On ne met jamais une sauvegarde dans Git. On n'a pas encore testé la restauration.
