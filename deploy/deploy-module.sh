#!/bin/bash

# args: network name; module name; module path; overwrite/nooverwrite to redeploy and commit new addresses; constructor abi or 'noargs'
# example: bash deploy/deploy-module.sh rinkeby overwrite Asks/V1.1/AsksV1_1.sol AsksV1_1 "constructor(address)"" "0xasdf"
# env: ETHERSCAN_API_KEY, <NETWORK_NAME>_CHAIN_ID, <NETWORK_NAME>_RPC_URL, <NETWORK_NAME>_PRIVATE_KEY, <NETWORK_NAME>_WALLET_ADDRESS, <NETWORK_NAME>_REGISTRAR, <NETWORK_NAME>_FEE_SETTINGS_OWNER

# supported chains (via ethers_rs which uses corresponding chain_ids):
# Mainnet
# Ropsten Kovan Rinkeby Goerli
# Polygon
# PolygonMumbai
# Avalanche
# AvalancheFuji
# Optimism
# OptimismKovan
# Fantom
# FantomTestnet
# BinanceSmartChain
# BinanceSmartChainTestnet
# Arbitrum
# ArbitrumTestnet
# Cronos

echo "Loading env..."
source .env

if [ "$1" = "" ]
then
    echo "Missing network name argument. Exiting."
    exit 1
fi
NETWORK_NAME=$(echo $1 | tr '[:lower:]' '[:upper:]')

if [ "$2" = "" ]
then
    echo "Missing overwrite/dontoverwrite argument. Exiting."
    exit 1
fi
if [ "$2" != "overwrite" ] && [ "$2" != "dontoverwrite" ]
then
    echo "Invalid overwrite/dontoverwrite argument. Exiting."
    exit 1
fi
OVERWRITE="$2"

if [ "$3" = "" ] || [ ! -f "./contracts/modules/$3" ]
then
    echo "Module path missing or incorrect. Exiting."
    exit 1
fi
MODULE_PATH="$3"

if [ "$4" = "" ]
then
    echo "Missing module name argument. Exiting."
    exit 1
fi
MODULE_NAME="$4"

CONSTRUCTOR_ABI=""
if [ "$5" = "" ]
then
    echo "Missing constructor abi argument. Exiting."
    exit 1
fi
if [ "$5" != "noargs" ] && [[ $5 != constructor* ]]
then
    echo "Invalid constructor abi argument. Exiting."
    exit 1
fi
if [[ $5 = constructor* ]]
then
    CONSTRUCTOR_ABI="$5"
    if [ -z "$6" ]
    then
        echo "Provided constructor abi but no constructor arguments. Exiting."
        exit 1
    fi
fi

CHAIN_ID_NAME="$NETWORK_NAME"_CHAIN_ID
CHAIN_ID="${!CHAIN_ID_NAME}"
if [ "$CHAIN_ID" = "" ]
then
    echo "Missing CHAIN_ID. Exiting."
    exit 1
fi

RPC_URL_NAME="$NETWORK_NAME"_RPC_URL
RPC_URL="${!RPC_URL_NAME}"
if [ "$RPC_URL" = "" ]
then
    echo "Missing RPC_URL. Exiting."
    exit 1
fi

PRIVATE_KEY_NAME="$NETWORK_NAME"_PRIVATE_KEY
PRIVATE_KEY="${!PRIVATE_KEY_NAME}"
if [ "$PRIVATE_KEY" = "" ]
then
    echo "Missing PRIVATE_KEY. Exiting."
    exit 1
fi

WALLET_ADDRESS_NAME="$NETWORK_NAME"_WALLET_ADDRESS
WALLET_ADDRESS="${!WALLET_ADDRESS_NAME}"
if [ "$WALLET_ADDRESS" = "" ]
then
    echo "Missing WALLET_ADDRESS. Exiting."
    exit 1
fi

REGISTRAR_NAME="$NETWORK_NAME"_REGISTRAR
REGISTRAR="${!REGISTRAR_NAME}"
if [ "$REGISTRAR" = "" ]
then
    echo "Missing REGISTRAR. Exiting."
    exit 1
fi

FEE_SETTINGS_OWNER_NAME="$NETWORK_NAME"_FEE_SETTINGS_OWNER
FEE_SETTINGS_OWNER="${!FEE_SETTINGS_OWNER_NAME}"
if [ "$FEE_SETTINGS_OWNER" = "" ]
then
    echo "Missing FEE_SETTINGS_OWNER. Exiting."
    exit 1
fi

ADDRESSES_FILENAME="addresses/$CHAIN_ID.json"
echo "Checking for existing contract addresses"
if EXISTING_ADDRESS=$(test -f "$ADDRESSES_FILENAME" && cat "$ADDRESSES_FILENAME" | python3 -c "import sys, json; print(json.load(sys.stdin)['$MODULE_NAME'])" 2> /dev/null)
then
    echo "$MODULE_NAME already exists on chain $CHAIN_ID at $EXISTING_ADDRESS."
    if [ $OVERWRITE = "dontoverwrite" ]
    then
        echo "Exiting."
        exit 1
    else
        echo "Continuing."
    fi
fi

# unset first 5 args, leaving only constructor args
shift 5

echo ""


echo "Deploying $MODULE_NAME..."
MODULE_DEPLOY_CMD="forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY $MODULE_NAME"
for arg in "$@"
do
    MODULE_DEPLOY_CMD="${MODULE_DEPLOY_CMD} --constructor-args $arg"
done
MODULE_DEPLOY_OUTPUT=$(${MODULE_DEPLOY_CMD})
MODULE_ADDR=$(echo $MODULE_DEPLOY_OUTPUT | rev | cut -d " " -f4 | rev)
if [[ $MODULE_ADDR =~ ^0x[0-9a-f]{40}$ ]]
then
    echo "$MODULE_NAME deployed to $MODULE_ADDR"
else
    echo "Could not find contract address in forge output"
    exit 1
fi
echo "Submitting contract to etherscan for verification..."
MODULE_VERIFY_CMD="forge verify-contract --chain-id $CHAIN_ID --num-of-optimizations 500000"
if [[ $CONSTRUCTOR_ABI = constructor* ]]
then
    MODULE_ENCODED_ARGS=$(cast abi-encode $CONSTRUCTOR_ABI "$@")
    MODULE_VERIFY_CMD="${MODULE_VERIFY_CMD} --constructor-args $MODULE_ENCODED_ARGS"
fi
MODULE_VERIFY_CMD="${MODULE_VERIFY_CMD} --compiler-version v0.8.10+commit.fc410830 $MODULE_ADDR contracts/modules/$MODULE_PATH:$MODULE_NAME $ETHERSCAN_API_KEY"
for I in 0 1 2 3 4
do
    {
        if MODULE_VERIFY_OUTPUT=$(${MODULE_VERIFY_CMD} 2> /dev/null)
        then
            echo "Submitted contract for verification."
            break
        else
            if (( 4 > $I ))
            then
                sleep 10
            else
                echo "Unable to submit contract verification. Exiting."
                exit 1
            fi
        fi
    }
done


echo ""
echo "Done."
