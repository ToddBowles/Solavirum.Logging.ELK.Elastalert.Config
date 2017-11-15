#!/bin/bash
echo -e "\nSTEP: Parsing command line options..."
OPTION_COUNT=0
while [[ $# -gt 1 ]]
do
KEY="$1"
OPTION_COUNT=$((OPTION_COUNT + 1))

case $KEY in
    -r|--rule)
    RULE="$2"
    shift
    ;;
    -e|--environment)
    ENVIRONMENT="$2"
    shift
    ;;
    *)
    echo "Unknown command line argument: $KEY."
    echo -e "...FAILURE\n"
    exit -1
    ;;
esac
shift
done

if [ -n "$RULE" ]; then
    echo "--rule option used. Will only run for rules that match: $RULE. This shouldn't happen anywhere other than local development"
fi

if [ -n "$ENVIRONMENT" ]; then
    echo "--environment option used, with value: $ENVIRONMENT. This shouldn't happen anywhere other than local development"
fi
echo -e "...SUCCESS\n"

CWD="$(pwd)"

echo -e "STEP: Determining Environmnet..."
if [ "$(type -t get_octopusvariable)" = function ]; then
    echo "get_octopusvariable function is defined => assuming we are running on Octopus"
    ENVIRONMENT=$(get_octopusvariable "Octopus.Environment.Name")
elif [ -n "$ENVIRONMENT" ]; then
    echo "--environment command line option was used"
else
    echo "Not running on Octopous and no --environment command line option used. Using 'Default'"
    ENVIRONMENT="Default"
fi
echo "ENVIRONMENT=$ENVIRONMENT"
echo -e "...SUCCESS\n"

echo -e "STEP: Create a new run directory..."
RUN_DIR=$CWD/runs/$(date +%Y%m%d_%H%M%S)
mkdir -p $RUN_DIR
mkdir -p $RUN_DIR/logs
echo "Created run directory $RUN_DIR"
echo -e "...SUCCESS\n"

echo -e "STEP: Copy files to run diectory..."
echo "Copying config files..."
HOST_CONFIG_DIR=$CWD/config
mkdir $RUN_DIR/config
cp $HOST_CONFIG_DIR/* $RUN_DIR/config/
HOST_RULES_DIR=$CWD/rules
if [ -n "$RULE" ]; then
    echo "Copying all rules that match pattern: $RULE" 
    mkdir $RUN_DIR/rules
    cp -r $HOST_RULES_DIR/$RULE $RUN_DIR/rules
else
    echo "Copying all rule files..."
    cp -r $HOST_RULES_DIR/ $RUN_DIR/rules
fi
echo -e "...SUCCESS\n"

echo -e "STEP: Resolve Sensitive substitutions (Octopus or Local)..."
declare -A -g SUBS
echo "Determining if running on Octopus or locally by checking for the get_octopusvariable function"
if [ "$(type -t get_octopusvariable)" = function ]; then
    RUNNING_LOCALLY=false
    SENSITIVE_FILE=$HOST_CONFIG_DIR/substitutions/Sensitive.Octopus.conf
    echo "get_octopusvariable is a defined function => This script is running on Octopus"
    echo "Creating a fresh file at $SENSITIVE_FILE"
    rm $SENSITIVE_FILE
    touch $SENSITIVE_FILE

    HIPCHAT_TOKEN_OCTOPUS="Elastalert.Hipchat.Token"
    echo "Reading HIPCHAT_TOKEN from Octopus variable: '$HIPCHAT_TOKEN_OCTOPUS'"
    HIPCHAT_TOKEN=$(get_octopusvariable "$HIPCHAT_TOKEN_OCTOPUS")
    echo -e "HIPCHAT_TOKEN=$HIPCHAT_TOKEN\n" >> $SENSITIVE_FILE
    
    # add anything else that needs to be read from Octopus here
else
    RUNNING_LOCALLY=true
    SENSITIVE_FILE=$HOST_CONFIG_DIR/substitutions/Sensitive.Local.conf
    echo "get_octopusvariable is NOT a defined function => This script is running locally"
fi
echo "Will use $SENSITIVE_FILE as the source of sensitive variables."
echo -e "...SUCCESS\n"

echo -e "STEP: Perform substitutions..."
python $CWD/substitute.py -e $ENVIRONMENT -s $HOST_CONFIG_DIR/substitutions -r $RUN_DIR -l $RUNNING_LOCALLY
if [ $? != 0 ]; then
    echo "Python substitutions failed"
    exit -1
fi
echo "Dot sourcing variables into scope"
. $RUN_DIR/Variables.conf
echo -e "...SUCCESS\n"

echo -e "STEP: Removing excluded rules files for environment $ENVIRONMENT..."
EXCLUSIONS_FILE=$HOST_CONFIG_DIR/rule_exclusions/rule_exclusions.$ENVIRONMENT.conf
echo "Loading exclusions file from $EXCLUSIONS_FILE"
declare -a EXCLUSIONS
readarray -t EXCLUSIONS < $EXCLUSIONS_FILE
if [ "${#EXCLUSIONS[@]}" -gt 0 ]; then
    for i in "${EXCLUSIONS[@]}" 
    do
        EXC_PATTERN=$(echo $i | tr -d '\r')
        REMOVE_PATH=$RUN_DIR/rules/$EXC_PATTERN
        echo "Removing rules that match $REMOVE_PATH"
        rm -f $REMOVE_PATH
        if [ $? != 0 ]; then
            echo "rm on $REMOVE_PATH failed"
            exit -1
        fi
    done
    echo "All matches removed"
else
    echo "No exclusion rules found"
fi
echo -e "...SUCCESS\n"

echo -e "STEP: Stop and remove existing docker containers..."
echo "Checking for any existing docker containers"
RUNNING_CONTAINERS=$(docker ps -a -q)
if [ -n "$RUNNING_CONTAINERS" ]; then
    echo "Found existing docker containers."
    echo "Stopping the following containers:"
    docker stop $(docker ps -a -q)
    echo "Removing the following containers:"
    docker rm $(docker ps -a -q)
    echo "All containers removed"
else
    echo "No existing containers found"
fi
echo -e "...SUCCESS\n"

echo -e "STEP: Run docker container..."
ELASTALERT_CONFIG_FILE="/opt/config/elastalert.yaml"
SUPERVISORD_CONFIG_FILE="/opt/config/supervisord.conf"
echo "Elastalert config file: $ELASTALERT_CONFIG_FILE"
echo "Supervisord config file: $SUPERVISORD_CONFIG_FILE"
echo "ES HOST: $ES_HOST"
echo "ES PORT: $ES_PORT"
docker run -d \
    -v $RUN_DIR/config:/opt/config \
    -v $RUN_DIR/rules:/opt/rules \
    -v $RUN_DIR/logs:/opt/logs \
    -e "ELASTALERT_CONFIG=$ELASTALERT_CONFIG_FILE" \
    -e "ELASTALERT_SUPERVISOR_CONF=$SUPERVISORD_CONFIG_FILE" \
    -e "ELASTICSEARCH_HOST=$ES_HOST" \
    -e "ELASTICSEARCH_PORT=$ES_PORT" \
    -e "SET_CONTAINER_TIMEZONE=true" \
    -e "CONTAINER_TIMEZONE=$TIMEZONE" \
    --cap-add SYS_TIME \
    --cap-add SYS_NICE $IMAGE_ID
if [ $? != 0 ]; then
    echo "docker run command returned a non-zero exit code."
    echo -e "...FAILED\n"
    exit -1
fi
CID=$(docker ps --latest --quiet)
echo "Elastalert container with ID $CID is now running"
echo -e "...SUCCESS\n"

echo -e "STEP: Checking for Elastalert process inside container..."
echo "Waiting 10 seconds for elastalert process"
sleep 10
if docker top $CID | grep -q elastalert; then
    echo "Found running Elastalert process. Nice."
else
    echo "Did not find elastalert running"
    echo "You can view logs for the container with: docker logs -f $CID"
    echo "You can shell into the container with: docker exec -it $CID sh"
    echo -e "...FAILURE\n"
    exit -1
fi
echo -e "...SUCCESS\n"