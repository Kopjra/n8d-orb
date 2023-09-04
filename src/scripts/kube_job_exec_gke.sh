#!/bin/bash
SQL_CONNECTION_STRING=${!SQL_CONNECTION_STRING_VARNAME}
GOOGLE_AUTH=${!GOOGLE_AUTH_VARNAME}

if [[ -z "${GOOGLE_AUTH}" ]]; then
  echo "GOOGLE_AUTH environmental variable must be set when using gcp"
  return -2
fi

case $NODE_ENV in

production)
NODE_ENV_SHORT=prod
;;

staging)
NODE_ENV_SHORT=stag
;;

development)
NODE_ENV_SHORT=dev
;;

test)
NODE_ENV_SHORT=test
;;

demo)
NODE_ENV_SHORT=demo
;;

*)
echo "Invalid NODE_ENV" specified
return -1
;;
esac

# Log into gcloud
echo ${GOOGLE_AUTH} > ${HOME}/gcp-key.json
gcloud auth activate-service-account --key-file ${HOME}/gcp-key.json
gcloud --quiet config set project ${GCP_PROJECT}
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --region=${GKE_CLUSTER_REGION}

RAND_ID=`echo $RANDOM | md5sum | head -c 10`

cat > job.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${APP_NAME_SHORT}-${NODE_ENV_SHORT}-job-$RAND_ID
  namespace: $NAMESPACE_NAME
spec:
  backoffLimit: 0
  completions: 1
  parallelism: 1
  activeDeadlineSeconds: 300
  template:
    spec:
      containers:
        - name: $APP_NAME_SHORT
          image: $DOCKER_IMAGE
          command: ["npm", "run", "${NPM_COMMAND}"]
          env:
          - name: DATABASE__SQL_CONNECTION_STRING
            value: "$SQL_CONNECTION_STRING"
          - name: NODE_ENV
            value: "$NODE_ENV"
      restartPolicy: Never
EOF

kubectl apply -n $NAMESPACE_NAME -f job.yaml

# wait for completion as background process or fails at timeout
kubectl wait --for=condition=complete job/${APP_NAME_SHORT}-${NODE_ENV_SHORT}-job-$RAND_ID -n=$NAMESPACE_NAME --timeout=300s