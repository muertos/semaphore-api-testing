#!/usr/bin/env bash

TOKEN=$1
PROJECT_ID=$2
SEMAPHORE_MYSQL_CT=$3

# set mysql env vars
source <(docker inspect $SEMAPHORE_MYSQL_CT --format '{{json .}}' | jq -r .Config.Env[] | grep MYSQL_)

# get ssh_key_id
SSH_KEY_ID=$(docker exec -it $SEMAPHORE_MYSQL_CT bash -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e \"select ssh_key_id from project__repository where project_id = $PROJECT_ID limit 1;\" 2>/dev/null | cat | grep -v ssh_key_id")

sleep 1

echo "Creating OM Tools repository"
curl -X 'POST' \
  "https://semaphore.pod-1.flexmetal.net/api/project/$PROJECT_ID/repositories" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
  \"name\": \"OM Tools\",
  \"project_id\": $PROJECT_ID,
  \"git_url\": \"git@git.imhadmin.net:flex-metal/playbooks/om-tools.git\",
  \"git_branch\": \"master\",
  \"ssh_key_id\": $SSH_KEY_ID
}"

# get inventory_id
INVENTORY_ID=$(docker exec -it $SEMAPHORE_MYSQL_CT bash -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e \"select inventory_id from project__template where project_id = $PROJECT_ID and name = 'Kolla Ansible';\" 2>/dev/null" | grep -oP "[0-9]+")
# get repository_id
REPOSITORY_ID=$(docker exec -it $SEMAPHORE_MYSQL_CT bash -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e \"select id from project__repository where project_id = $PROJECT_ID and name = 'OM Tools';\" 2>/dev/null" | grep -oP "[0-9]+")
# get environment_id
ENVIRONMENT_ID=$(docker exec -it $SEMAPHORE_MYSQL_CT bash -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e \"select environment_id from project__template where project_id = $PROJECT_ID and name = 'Kolla Ansible';\" 2>/dev/null" | grep -oP "[0-9]+")
# get view_id
VIEW_ID=$(docker exec -it $SEMAPHORE_MYSQL_CT bash -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e \"select view_id from project__template where project_id = $PROJECT_ID and name = 'Kolla Ansible';\" 2>/dev/null" | grep -oP "[0-9]+")

echo "Creating update node-agent task template"
TEMPLATE_ID=$(curl -X 'POST' \
  "https://semaphore.pod-1.flexmetal.net/api/project/$PROJECT_ID/templates" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
  \"project_id\": $PROJECT_ID,
  \"inventory_id\": $INVENTORY_ID,
  \"repository_id\": $REPOSITORY_ID,
  \"environment_id\": $ENVIRONMENT_ID,
  \"view_id\": $VIEW_ID,
  \"name\": \"Update node-agent\",
  \"playbook\": \"update-node-agent/site.yml\",
  \"arguments\": \"[]\",
  \"description\": \"\",
  \"override_args\": true
}" | jq -r .id)

sleep 1

echo "Launching update node-agent task template"
curl -X 'POST' \
  "https://semaphore.pod-1.flexmetal.net/api/project/$PROJECT_ID/tasks" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
  \"template_id\": $TEMPLATE_ID,
  \"debug\": false,
  \"dry_run\": false,
  \"playbook\": \"update-node-agent/site.yml\",
  \"environment\": \"{}\"
}"

# wait for previous task to finish
sleep 35 

echo "Removing task template"
curl -X 'DELETE' \
  "https://semaphore.pod-1.flexmetal.net/api/project/$PROJECT_ID/templates/$TEMPLATE_ID" \
  -H 'accept: application/json' \
  -H "Authorization: Bearer $TOKEN"

echo "Removing OM Tools repository"
curl -X 'DELETE' \
  "https://semaphore.pod-1.flexmetal.net/api/project/$PROJECT_ID/repositories/$REPOSITORY_ID" \
  -H 'accept: application/json' \
  -H "Authorization: Bearer $TOKEN"
