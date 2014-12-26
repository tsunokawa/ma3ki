#!/bin/sh
#
# created by ma3ki@ma3ki.net at 2014/12/10
#
# please install mutt command
# yum install mutt
#
# For example
# ./sendimgmail.sh <mailAddress> <subject> <message>

export LANG=ja_JP.utf8

### READ CONFIG
CURRENT_PATH=`dirname $0`
source ${CURRENT_PATH}/sendimgmail.conf
AUTH=""

######## zabbix_api #######
# usage)
# zabbix_api <url> <method> <param1> <param2> ....
#
# user.login
#   <param1> = username
#   <param2> = password
#   Return   = sessionid
# 
# host.get,item.get,graph.get
#   <param1> = sessionid
#   <param2> = return field
#   <param3> = output rule
#   <param3> = filter rule
#   Return   = fieldid
###########################
zabbix_api() {

  HEADER="Content-Type:application/json-rpc"

  URL=$1
  METHOD=$2

  # check basic authentication
  if [ "${BASIC_USER}x" != "x" ]
  then
    AUTH="--user ${BASIC_USER}:${BASIC_PASS}"
  fi

  case ${METHOD} in
    user.login)
      ### get sessionid
      USER=$3
      PASSWORD=$4
      JSONTEMP=`curl ${AUTH} -X GET -H ${HEADER} -d "{
        \"auth\":null,
        \"method\":\"${METHOD}\",
        \"id\":1,
        \"params\":{
          \"user\":\"${USER}\",
          \"password\":\"${PASSWORD}\"
        }, \"jsonrpc\":\"2.0\"
      }" ${URL} 2>/dev/null`

      RESULT=`echo "${JSONTEMP}" | sed -e 's/[,{}]/\n/g' -e 's/"//g' | awk -F: '/^result/{print $2}'`

      ;;
    *.get)
      ### get result
      SESSIONID=$3
      RETURN=$4
      OUTPUT=""
      FILTER=""
      for x in `seq 5 $#`
      do
        ARGV=`eval echo \"'\$'${x}\"`
        if [ `echo ${ARGV} | grep -c "output"` -eq 1 ]
        then
          OUTPUT=${ARGV}
        elif [ `echo ${ARGV} | grep -c "filter"` -eq 1 ]
        then
          FILTER=${ARGV}
        fi
      done
       
      if [ ${METHOD} = "graph.get" ]
      then
        JSONTEMP=`curl ${AUTH} -X GET -H ${HEADER} -d "{
          \"auth\":\"${SESSIONID}\",
          \"method\":\"${METHOD}\",
          \"id\":1,
          \"params\":{
            ${OUTPUT}
          }, \"jsonrpc\":\"2.0\"
        }" ${URL} 2>/dev/null`
      else 
        JSONTEMP=`curl ${AUTH} -X GET -H ${HEADER} -d "{
          \"auth\":\"${SESSIONID}\",
          \"method\":\"${METHOD}\",
          \"id\":1,
          \"params\":{
            ${OUTPUT},
            ${FILTER}
          }, \"jsonrpc\":\"2.0\"
        }" ${URL} 2>/dev/null`
      fi

      RESULT=`echo "${JSONTEMP}" | sed -e 's/[,{}]/\n/g' -e 's/"//g' | awk -F: "/^${RETURN}:/{print \\$2}"`
      ;;
    *)
      ;;
  esac

  if [ "${RESULT}x" = "x" ]
  then
    echo "${METHOD}_request_failed"
  fi

  echo ${RESULT}
}

### main
if [ ! -d ${HOME} ]
then
  echo "${HOME} is not found."
  exit 1
fi

if [ ! -d ${IMAGE_TEMP} ]
then
  mkdir ${IMAGE_TEMP}
fi

RCPT="$1"
SUBJ="$2"
DATA=`echo "$3" | tr -d '\r'`

### get graph infomation
HOST=`echo "${DATA}" | grep "^host:" | sed -r 's/host:\s?//'`
KEY=`echo "${DATA}" | grep "^key:" | sed -r 's/key:\s?//'`

### get graphids
sessionid=`zabbix_api ${ZABBIX_API} "user.login" ${ZABBIX_USER} ${ZABBIX_PASS}`
hostid=`zabbix_api ${ZABBIX_API} "host.get" ${sessionid} "hostid" "\"output\":[\"hostid\"]" "\"filter\":{\"host\":\"${HOST}\"}"`
itemid=`zabbix_api ${ZABBIX_API} "item.get" ${sessionid} "itemid" "\"output\":[\"itemid\"]" "\"filter\":{\"hostid\":\"${hostid}\",\"key_\":\"${KEY}\"}"`
graphids=`zabbix_api ${ZABBIX_API} "graph.get" ${sessionid} "graphid" "\"output\":\"graphid\",\"hostids\":\"${hostid}\",\"itemids\":\"${itemid}\""`

### get graph images
MTMP=""
if [ `echo ${graphids} | grep -c "graph.get_request_failed"` -ne 1 ]
then
  START_TIME=`date -d "${GRAPH_START}" +%s`
  for x in `echo ${graphids}`
  do
    curl ${AUTH} -X GET -b zbx_sessionid=${sessionid} "${ZABBIX_GRAPH}?graphid=${x}&width=${GRAPH_WIDTH}&period=${GRAPH_PERIOD}&stime=${START_TIME}" > ${IMAGE_TEMP}/${x}.png 2>/dev/null
    MTMP=`echo "${MTMP} -a ${IMAGE_TEMP}/${x}.png"`
  done
fi

### set email address
cat <<EOF > ${IMAGE_TEMP}/mutt.txt
set from='${MAIL_FROM}'
set realname='${MAIL_NAME}'
set envelope_from=yes
EOF

### send mail
if [ "${MTMP}x" != "x" ]
then
  echo "${DATA}" | mutt -s "${SUBJ}" -F ${IMAGE_TEMP}/mutt.txt "${RCPT}" ${MTMP}
else
  echo "${DATA}" | mutt -s "${SUBJ}" -F ${IMAGE_TEMP}/mutt.txt "${RCPT}"
fi

exit 0
