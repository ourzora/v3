#!/bin/bash

# args: 'overwrite'/'dontoverwrite'; module path; module name; constructor abi in quotes or 'noargs'; any constructor args separated by spaces
# example: bash deploy/deploy-module.sh overwrite Asks/V1.1/AsksV1_1.sol AsksV1_1 "constructor(address)" "0xasdf"
# env: ETHERSCAN_API_KEY, CHAIN_ID, RPC_URL, PRIVATE_KEY

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

if [ "$ETHERSCAN_API_KEY" = "" ]
then
    echo "Missing ETHERSCAN_API_KEY. Exiting."
    exit 1
fi

if [ "$CHAIN_ID" = "" ]
then
    echo "Missing CHAIN_ID. Exiting."
    exit 1
fi

if [ "$RPC_URL" = "" ]
then
    echo "Missing RPC_URL. Exiting."
    exit 1
fi

if [ "$PRIVATE_KEY" = "" ]
then
    echo "Missing PRIVATE_KEY. Exiting."
    exit 1
fi

if [ "$WALLET_ADDRESS" = "" ]
then
    echo "Missing WALLET_ADDRESS. Exiting."
    exit 1
fi

if [ "$1" = "" ]
then
    echo "Missing overwrite/dontoverwrite argument. Exiting."
    exit 1
fi
if [ "$1" != "overwrite" ] && [ "$1" != "dontoverwrite" ]
then
    echo "Invalid overwrite/dontoverwrite argument. Exiting."
    exit 1
fi
OVERWRITE="$1"

if [ "$2" = "" ] || [ ! -f "./contracts/modules/$2" ]
then
    echo "Module path missing or incorrect. Exiting."
    exit 1
fi
MODULE_PATH="$2"

if [ "$3" = "" ]
then
    echo "Missing module name argument. Exiting."
    exit 1
fi
MODULE_NAME="$3"

CONSTRUCTOR_ABI=""
if [ "$4" = "" ]
then
    echo "Missing constructor abi argument. Exiting."
    exit 1
fi
if [ "$4" != "noargs" ] && [[ $4 != f* ]]
then
    echo "Invalid constructor abi argument. Exiting."
    exit 1
fi
if [[ $4 = f* ]]
then
    CONSTRUCTOR_ABI="$4"
    if [ -z "$5" ]
    then
        echo "Provided constructor abi but no constructor arguments. Exiting."
        exit 1
    fi
fi

if [ "$CHAIN_ID" = "" ]
then
    echo "Missing CHAIN_ID. Exiting."
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

# unset first 4 args, leaving only constructor args
shift 4

echo ""

echo "Deploying $MODULE_NAME..."
MODULE_DEPLOY_CMD="forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY $MODULE_NAME"
if (($# > 0))
then
    MODULE_DEPLOY_CMD="${MODULE_DEPLOY_CMD} --constructor-args"
fi
for arg in "$@"
do
    MODULE_DEPLOY_CMD="${MODULE_DEPLOY_CMD} $arg"
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
MODULE_ADDR=$(cast --to-checksum-address $MODULE_ADDR)
echo "Submitting contract to etherscan for verification..."
MODULE_VERIFY_CMD="forge verify-contract --chain-id $CHAIN_ID --num-of-optimizations 500000"
if [[ $CONSTRUCTOR_ABI = f* ]]
then
    MODULE_ENCODED_ARGS=$(cast abi-encode $CONSTRUCTOR_ABI "$@")
    MODULE_VERIFY_CMD="${MODULE_VERIFY_CMD} --constructor-args $MODULE_ENCODED_ARGS"
fi
MODULE_VERIFY_CMD="${MODULE_VERIFY_CMD} --compiler-version v0.8.10+commit.fc410830 $MODULE_ADDR contracts/modules/$MODULE_PATH:$MODULE_NAME $ETHERSCAN_API_KEY"
for I in 0 1 2 3 4
do
    {
        if MODULE_VERIFY_OUTPUT=$(${MODULE_VERIFY_CMD})
        then
            echo "Submitted contract for verification."
            echo "Output:"
            echo "$MODULE_VERIFY_OUTPUT"
            break
        else
            if (( 4 > $I ))
            then
                sleep 20
            else
                echo "Unable to submit contract verification. Exiting."
                exit 1
            fi
        fi
    }
done

python3 ./deploy/update-addresses.py $CHAIN_ID $MODULE_NAME $MODULE_ADDR

echo ""
echo "Done."
