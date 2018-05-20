FROM centos:7

# install python
ARG PYTHON_VERSION="3.6.0"

RUN yum install -y gcc gcc-c++ make openssl-devel\
  && curl https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz | tar -xzf -  -C /usr/src/ \
  && cd /usr/src/Python-${PYTHON_VERSION} \
  && ./configure && make install \
  && curl "https://bootstrap.pypa.io/get-pip.py" | python  \
  && pip install virtualenv \
  && rm -rf /var/cache/apk/* && rm -rf /usr/src/Python-*

RUN cd /usr/local/bin \
	&& ln -s idle3 idle \
	&& ln -s pydoc3 pydoc \
	&& ln -s python3 python \
	&& ln -s python3-config python-config \
	&& ln -s pip3 pip

ENV PATH "/usr/local/bin:${PATH}"

RUN yum -y update && \
    yum -y install epel-release && \
    yum -y install \
        nmap-ncat \
        python-pip \
        python-devel \
        mariadb-libs \
        mariadb-devel \
        krb5-devel \
        cyrus-sasl \
        cyrus-sasl-devel \
        cyrus-sasl-gs2 \
        cyrus-sasl-gssapi \
        cyrus-sasl-lib \
        cyrus-sasl-md5 \
        cyrus-sasl-plain \
        openssl-devel \
        libffi-devel \
        krb5-workstation \
        which \
        cronie-noanacron \
        sudo \
        wget \
        unzip \
        libaio-devel



ENV ORACLE_HOME /opt/oracle/instantclient_12_1
ENV LD_LIBRARY_PATH=$ORACLE_HOME

COPY pre_src/oracle_instantclient/* /tmp/


RUN mkdir -p /opt/oracle && \
    unzip "/tmp/instantclient*.zip" -d /opt/oracle && \
    ln -s $ORACLE_HOME/libclntsh.so.12.1 $ORACLE_HOME/libclntsh.so

ARG AIRFLOW_VERSION=1.9.0
ENV AIRFLOW_HOME /home/airflow
ENV AIRFLOW_USER_ID 8724

RUN useradd -ms /bin/bash -d $AIRFLOW_HOME -u $AIRFLOW_USER_ID -o -c "" airflow \
    && python -m pip install -U pip setuptools wheel \
    && pip install Cython \
    && pip install pytz \
    && pip install pyOpenSSL \
    && pip install ndg-httpsclient \
    && pip install pyasn1 \
    && pip install apache-airflow[crypto,celery,postgres,hive,jdbc]==$AIRFLOW_VERSION \
    && pip install celery[redis]==3.1.17 \
    && pip install flask-bcrypt \
    && pip install cx_Oracle \
    && pip install hdfs \
    && pip install paramiko \
    && yum -y clean all \
    && rm -rf /tmp/* /var/tmp/*

COPY pre_script/entrypoint.sh /entrypoint.sh
COPY pre_script/setup_auth.py $AIRFLOW_HOME/setup_auth.py
COPY pre_config/airflow.cfg $AIRFLOW_HOME/airflow.cfg
COPY pre_config/celeryconfig.py /usr/local/lib/python3.6/site-packages/airflow/celeryconfig.py

RUN mkdir -p $AIRFLOW_HOME/data
RUN mkdir -p $AIRFLOW_HOME/dags
RUN mkdir -p $AIRFLOW_HOME/logs
RUN mkdir -p $AIRFLOW_HOME/plugins

RUN chown -R airflow: $AIRFLOW_HOME

ENV EXECUTOR Celery

ENV REDIS_HOST localhost
ENV REDIS_PORT 6379
#ENV REDIS_PASSWORD 

ENV POSTGRES_HOST localhost
ENV POSTGRES_PORT 5432
ENV POSTGRES_USER airflow
ENV POSTGRES_PASSWORD airflow
ENV POSTGRES_DB airflow

ENV LOAD_EXAMPLES y
ENV FERNET_KEY 46BKJoQYlPPOexq0OhDZnIlNepKFf87WFwLbfzqDDho=

ENV AIRFLOW_PORT 7777
ENV FLOWER_PORT 5555
ENV WORKER_LOG_PORT 8793


USER airflow
WORKDIR $AIRFLOW_HOME
ENTRYPOINT ["/entrypoint.sh"]
