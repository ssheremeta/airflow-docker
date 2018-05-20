#!/usr/bin/env bash

CMD="airflow"
TRY_LOOP="10"

# Temporary workaround for disabling warnings in Airflow version = 1.8.2
sed -i "s#from flask_wtf.csrf import CsrfProtect#from flask_wtf.csrf import CSRFProtect#" /usr/local/lib/python3.6/site-packages/airflow/www/app.py
sed -i "s#csrf = CsrfProtect()#csrf = CSRFProtect()#" /usr/local/lib/python3.6/site-packages/airflow/www/app.py


# Update airflow home if it difference from default - /home/airflow
if [ "$AIRFLOW_HOME" != "/home/airflow" ]; then
    sed -i "s#airflow_home = /home/airflow#airflow_home = $AIRFLOW_HOME#" "$AIRFLOW_HOME"/airflow.cfg
    sed -i "s#dags_folder = /home/airflow/dags#dags_folder = $AIRFLOW_HOME/dags#" "$AIRFLOW_HOME"/airflow.cfg
    sed -i "s#base_log_folder = /home/airflow/logs#base_log_folder = $AIRFLOW_HOME/logs#" "$AIRFLOW_HOME"/airflow.cfg
    sed -i "s#plugins_folder = /home/airflow/plugins#plugins_folder = $AIRFLOW_HOME/plugins#" "$AIRFLOW_HOME"/airflow.cfg
    sed -i "s#child_process_log_directory = /home/airflow/logs/scheduler#child_process_log_directory = $AIRFLOW_HOME/logs/scheduler#" "$AIRFLOW_HOME"/airflow.cfg
    sed -i "s#access_logfile = /home/airflow/logs/webserver-access.log#access_logfile = $AIRFLOW_HOME/logs/webserver-access.log#" "$AIRFLOW_HOME"/airflow.cfg
    sed -i "s#error_logfile = /home/airflow/logs/webserver-error.log#error_logfile = $AIRFLOW_HOME/logs/webserver-error.log#" "$AIRFLOW_HOME"/airflow.cfg
fi

# Update airflow port if it difference from default - 7777
if [ -n "$AIRFLOW_PORT" ]; then
    sed -i "s#endpoint_url = http://localhost:7777#endpoint_url = http://localhost:$AIRFLOW_PORT#" "$AIRFLOW_HOME"/airflow.cfg
    sed -i "s#base_url = http://localhost:7777#base_url = http://localhost:$AIRFLOW_PORT#" "$AIRFLOW_HOME"/airflow.cfg
    sed -i "s#web_server_port = 7777#web_server_port = $AIRFLOW_PORT#" "$AIRFLOW_HOME"/airflow.cfg
fi

# Update airflow port if it difference from default - 7777
if [ -n "$FLOWER_PORT" ]; then
    sed -i "s#flower_port = 5555#flower_port = $FLOWER_PORT#" "$AIRFLOW_HOME"/airflow.cfg
fi


# Load DAGs examples (default: Yes)
if [ "$LOAD_EXAMPLES" = "n" ]; then
    sed -i "s/load_examples = True/load_examples = False/" "$AIRFLOW_HOME"/airflow.cfg
fi

# Install custome python package if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    $(which pip) install --user -r /requirements.txt
fi

# Update airflow config - Fernet key
sed -i "s|\$FERNET_KEY|$FERNET_KEY|" "$AIRFLOW_HOME"/airflow.cfg

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_PREFIX=:${REDIS_PASSWORD}@
else
    REDIS_PREFIX=
fi

# Wait for Postresql
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] ; then
  i=0
  while ! nc --send-only $POSTGRES_HOST $POSTGRES_PORT >/dev/null 2>&1 < /dev/null; do
    i=$((i+1))
    if [ "$1" = "webserver" ]; then
      echo "$(date) - waiting for ${POSTGRES_HOST}:${POSTGRES_PORT}... $i/$TRY_LOOP"
      if [ $i -ge $TRY_LOOP ]; then
        echo "$(date) - ${POSTGRES_HOST}:${POSTGRES_PORT} still not reachable, giving up"
        exit 1
      fi
    fi
    sleep 10
  done
fi

# Update configuration depending the type of Executor
if [ "$EXECUTOR" = "Celery" ]
then
  # Wait for Redis
  if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] || [ "$1" = "flower" ] ; then
    j=0
    while ! nc --send-only $REDIS_HOST $REDIS_PORT >/dev/null 2>&1 < /dev/null; do
      j=$((j+1))
      if [ $j -ge $TRY_LOOP ]; then
        echo "$(date) - $REDIS_HOST still not reachable, giving up"
        exit 1
      fi
      echo "$(date) - waiting for Redis... $j/$TRY_LOOP"
      sleep 5
    done
  fi
  sed -i "s#celery_result_backend = db+postgresql://airflow:airflow@postgres/airflow#celery_result_backend = db+postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB#" "$AIRFLOW_HOME"/airflow.cfg
  sed -i "s#sql_alchemy_conn = postgresql+psycopg2://airflow:airflow@postgres/airflow#sql_alchemy_conn = postgresql+psycopg2://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB#" "$AIRFLOW_HOME"/airflow.cfg
  sed -i "s#broker_url = redis://redis:6379/1#broker_url = redis://$REDIS_PREFIX$REDIS_HOST:$REDIS_PORT/1#" "$AIRFLOW_HOME"/airflow.cfg

  if [ "$1" = "webserver" ]; then
    echo "Initialize database...1"
    $CMD initdb
    echo "Creating user...1"
    python "${AIRFLOW_HOME}"/setup_auth.py
    exec $CMD webserver
  else
    sleep 10
    exec $CMD "$@"
  fi
elif [ "$EXECUTOR" = "Local" ]
then
  sed -i "s/executor = CeleryExecutor/executor = LocalExecutor/" "$AIRFLOW_HOME"/airflow.cfg
  sed -i "s#sql_alchemy_conn = postgresql+psycopg2://airflow:airflow@postgres/airflow#sql_alchemy_conn = postgresql+psycopg2://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB#" "$AIRFLOW_HOME"/airflow.cfg
  sed -i "s#broker_url = redis://redis:6379/1#broker_url = redis://$REDIS_PREFIX$REDIS_HOST:$REDIS_PORT/1#" "$AIRFLOW_HOME"/airflow.cfg
  echo "Initialize database...2"
  $CMD initdb
  echo "Creating user...2"
  python "${AIRFLOW_HOME}"/setup_auth.py
  exec $CMD webserver &
  exec $CMD scheduler
# By default we use SequentialExecutor
else
  if [ "$1" = "version" ]; then
    exec $CMD version
    exit
  fi
  sed -i "s/executor = CeleryExecutor/executor = SequentialExecutor/" "$AIRFLOW_HOME"/airflow.cfg
  sed -i "s#sql_alchemy_conn = postgresql+psycopg2://airflow:airflow@postgres/airflow#sql_alchemy_conn = sqlite:////usr/local/airflow/airflow.db#" "$AIRFLOW_HOME"/airflow.cfg
  echo "Initialize database...3"
  $CMD initdb
  echo "Creating user...3"
  python "${AIRFLOW_HOME}"/setup_auth.py
  exec $CMD webserver
fi