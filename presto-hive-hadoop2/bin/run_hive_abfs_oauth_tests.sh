#!/usr/bin/env bash
set -euxo pipefail

. "${BASH_SOURCE%/*}/common.sh"

test -v ABFS_ACCOUNT
test -v ABFS_CONTAINER
test -v ABFS_OAUTH_CLIENT_ENDPOINT
test -v ABFS_OAUTH_CLIENT_ID
test -v ABFS_OAUTH_CLIENT_SECRET

test_directory="$(date '+%Y%m%d-%H%M%S')-$(uuidgen | sha1sum | cut -b 1-6)"

cleanup_hadoop_docker_containers
start_hadoop_docker_containers

# insert Azure credentials
deploy_core_site_xml core-site.xml.abfs-oauth-template \
    ABFS_ACCOUNT ABFS_CONTAINER \
    ABFS_OAUTH_CLIENT_ENDPOINT ABFS_OAUTH_CLIENT_ID ABFS_OAUTH_CLIENT_SECRET

# restart services to apply changes in core-site.xml
exec_in_hadoop_master_container \
    supervisorctl restart hive-metastore hive-server2
retry check_hadoop

create_test_tables \
    "abfs://$ABFS_CONTAINER@$ABFS_ACCOUNT.dfs.core.windows.net/$test_directory"

stop_unnecessary_hadoop_services

pushd $PROJECT_ROOT
set +e
./mvnw -B -pl presto-hive-hadoop2 test -P test-hive-hadoop2-abfs-oauth \
    -DHADOOP_USER_NAME=hive \
    -Dhive.hadoop2.metastoreHost=localhost \
    -Dhive.hadoop2.metastorePort=9083 \
    -Dhive.hadoop2.databaseName=default \
    -Dtest.hive.azure.abfs.container="$ABFS_CONTAINER" \
    -Dtest.hive.azure.abfs.storage-account="$ABFS_ACCOUNT" \
    -Dtest.hive.azure.abfs.test-directory="$test_directory" \
    -Dhive.azure.abfs.oauth-client-endpoint="$ABFS_OAUTH_CLIENT_ENDPOINT" \
    -Dhive.azure.abfs.oauth-client-id="$ABFS_OAUTH_CLIENT_ID" \
    -Dhive.azure.abfs.oauth-client-secret="$ABFS_OAUTH_CLIENT_SECRET"
EXIT_CODE=$?
set -e
popd

cleanup_hadoop_docker_containers

exit ${EXIT_CODE}