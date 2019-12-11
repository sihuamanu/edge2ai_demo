BASE_DIR=$(cd $(dirname $0); pwd -P)
SSH_USER="root"
echo "-- Configure and start EFM"
retries=0
while true; do
  mysql -u efm -pcloudera < <( echo -e "drop database efm;\ncreate database efm;" )
  nohup service efm start &
  sleep 10
  set +e
  ps -ef | grep  efm.jar | grep -v grep
  cnt=$(ps -ef | grep  efm.jar | grep -v grep | wc -l)
  set -e
  if [ "$cnt" -gt 0 ]; then
    break
  fi
  if [ "$retries" == "5" ]; then
    break
  fi
  retries=$((retries + 1))
  echo "Retrying to start EFM ($retries)"
done

echo "-- Enable and start MQTT broker"
systemctl enable mosquitto
systemctl start mosquitto

echo "-- Copy demo files to a public directory"
mkdir -p /opt/demo
cp -f $BASE_DIR/simulate.py /opt/demo/
cp -f $BASE_DIR/spark.iot.py /opt/demo/
chmod -R 775 /opt/demo

echo "-- Start MiNiFi"
systemctl enable minifi
systemctl start minifi

# TODO: Implement Ranger DB and Setup in template
# TODO: Fix kafka topic creation once Ranger security is setup
echo "-- Create Kafka topic (iot)"
kafka-topics --zookeeper edge2ai-1.dim.local:2181/kafka --create --topic iot --partitions 10 --replication-factor 1
kafka-topics --zookeeper edge2ai-1.dim.local:2181/kafka --describe --topic iot

#if [[ -n "$FLINK_BUILD" && "$CDH_MAJOR_VERSION" == "6" ]]; then # TODO: Change this when Flink is available for CDP-DC
if [[ "1" = "1"  ]]; then # TODO: Change this when Flink is available for CDP-DC
  echo "-- Flink: extra workaround due to CSA-116"
  sudo -u hdfs hdfs dfs -chown flink:flink /user/flink
  sudo -u hdfs hdfs dfs -mkdir /user/${SSH_USER}
  sudo -u hdfs hdfs dfs -chown ${SSH_USER}:${SSH_USER} /user/${SSH_USER}

  echo "-- Runs a quick Flink WordCount to ensure everything is ok"
  echo "foo bar" > echo.txt
  export HADOOP_USER_NAME=flink
  hdfs dfs -put echo.txt
  flink run -sae -m yarn-cluster -p 2 /opt/cloudera/parcels/FLINK/lib/flink/examples/streaming/WordCount.jar --input hdfs:///user/$HADOOP_USER_NAME/echo.txt --output hdfs:///user/$HADOOP_USER_NAME/output
  hdfs dfs -cat hdfs:///user/$HADOOP_USER_NAME/output/*
  unset HADOOP_USER_NAME
fi

echo "-- At this point you can login into Cloudera Manager host on port 7180 and follow the deployment of the cluster"

# Finish install
