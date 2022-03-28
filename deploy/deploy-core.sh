#!/bin/bash

# args: network name; 'overwrite' or 'dontoverwrite' to redeploy and commit new addresses
# env: ETHERSCAN_API_KEY, <NETWORK_NAME>_CHAIN_ID, <NETWORK_NAME>_RPC_URL, <NETWORK_NAME>_PRIVATE_KEY, <NETWORK_NAME>_WALLET_ADDRESS, <NETWORK_NAME>_REGISTRAR, <NETWORK_NAME>_FEE_SETTINGS_OWNER

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
if EXISTING_ADDRESS=$(test -f "$ADDRESSES_FILENAME" && cat "$ADDRESSES_FILENAME" | python3 -c "import sys, json; print(json.load(sys.stdin)['ZoraProtocolFeeSettings'])" 2> /dev/null)
then
    echo "ZoraProtocolFeeSettings already exists on chain $CHAIN_ID at $EXISTING_ADDRESS."
    if [ "$2" != "overwrite" ]
        echo "Exiting."
        exit 1
    else
        echo "Continuing."
    fi
fi
if EXISTING_ADDRESS=$(test -f "$ADDRESSES_FILENAME" && cat "$ADDRESSES_FILENAME" | python3 -c "import sys, json; print(json.load(sys.stdin)['ZoraModuleManager'])" 2> /dev/null)
then
    echo "ZoraModuleManager already exists on chain $CHAIN_ID at $EXISTING_ADDRESS."
    if [ "$2" != "overwrite" ]
        echo "Exiting."
        exit 1
    else
        echo "Continuing."
    fi
fi

echo ""


echo "Deploying ZoraProtocolFeeSettings..."
FEE_SETTINGS_DEPLOY_OUTPUT=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY ZoraProtocolFeeSettings)
FEE_SETTINGS_ADDR=$(echo $FEE_SETTINGS_DEPLOY_OUTPUT | rev | cut -d " " -f4 | rev)
if [[ $FEE_SETTINGS_ADDR =~ ^0x[0-9a-f]{40}$ ]]
then
    echo "ZoraProtocolFeeSettings deployed to $FEE_SETTINGS_ADDR"
else
    echo "Could not find contract address in forge output"
    exit 1
fi
echo "Submitting contract to etherscan for verification..."
for I in 0 1 2 3 4
do
    {
        if FEE_SETTINGS_VERIFY_OUTPUT=$(forge verify-contract --chain-id $CHAIN_ID --num-of-optimizations 500000 --compiler-version v0.8.10+commit.fc410830 "$FEE_SETTINGS_ADDR" contracts/auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol:ZoraProtocolFeeSettings "$ETHERSCAN_API_KEY" 2> /dev/null)
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


echo "Deploying ZoraModuleManager..."
MODULE_MANAGER_DEPLOY_OUTPUT=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY ZoraModuleManager --constructor-args "$REGISTRAR" --constructor-args "$FEE_SETTINGS_ADDR")
MODULE_MANAGER_ADDR=$(echo $MODULE_MANAGER_DEPLOY_OUTPUT | rev | cut -d " " -f4 | rev)
if [[ $MODULE_MANAGER_ADDR =~ ^0x[0-9a-f]{40}$ ]]
then
    echo "ZoraModuleManager deployed to $MODULE_MANAGER_ADDR"
else
    echo "Could not find contract address in forge output"
    echo $MODULE_MANAGER_DEPLOY_OUTPUT
    exit 1
fi
echo "Submitting contract to etherscan for verification..."
MODULE_MANAGER_ENCODED_ARGS=$(cast abi-encode "constructor(address,address)" "$REGISTRAR" "$FEE_SETTINGS_ADDR")
for I in 0 1 2 3 4
do
    {
        if MODULE_MANAGER_VERIFY_OUTPUT=$(forge verify-contract --chain-id $CHAIN_ID --num-of-optimizations 500000 --constructor-args "$MODULE_MANAGER_ENCODED_ARGS" --compiler-version v0.8.10+commit.fc410830 "$MODULE_MANAGER_ADDR" contracts/ZoraModuleManager.sol:ZoraModuleManager "$ETHERSCAN_API_KEY" 2> /dev/null)
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

FEE_SETTINGS_INIT_OUTPUT=$(cast send --from $WALLET_ADDRESS --private-key $PRIVATE_KEY $FEE_SETTINGS_ADDR "init(address,address)" "$MODULE_MANAGER_ADDR" "0x0000000000000000000000000000000000000000" --rpc-url $RPC_URL)
FEE_SETTINGS_INIT_TX_HASH=$(echo $FEE_SETTINGS_INIT_OUTPUT | rev | cut -d " " -f5 | rev | tr -d '"')
FEE_SETTINGS_INIT_TX_STATUS=$(echo $FEE_SETTINGS_INIT_OUTPUT | rev | cut -d " " -f7 | rev | tr -d '"')
if [ $FEE_SETTINGS_INIT_TX_STATUS != "0x1" ]
then
    echo "Transaction $FEE_SETTINGS_INIT_TX_HASH did not succeed. Exiting."
    exit 1
else
    echo "ZoraProtocolFeeSettings.init transaction $FEE_SETTINGS_INIT_TX_HASH succeeded."
fi

FEE_SETTINGS_SET_OWNER_OUTPUT=$(cast send --from $WALLET_ADDRESS --private-key $PRIVATE_KEY $FEE_SETTINGS_ADDR "setOwner(address)" "$FEE_SETTINGS_OWNER" --rpc-url $RPC_URL)
FEE_SETTINGS_SET_OWNER_TX_HASH=$(echo $FEE_SETTINGS_SET_OWNER_OUTPUT | rev | cut -d " " -f5 | rev | tr -d '"')
FEE_SETTINGS_SET_OWNER_TX_STATUS=$(echo $FEE_SETTINGS_SET_OWNER_OUTPUT | rev | cut -d " " -f7 | rev | tr -d '"')
if [ $FEE_SETTINGS_SET_OWNER_TX_STATUS != "0x1" ]
then
    echo "Transaction $FEE_SETTINGS_SET_OWNER_TX_HASH did not succeed. Exiting."
    exit 1
else
    echo "ZoraProtocolFeeSettings.setOwner transaction $FEE_SETTINGS_SET_OWNER_TX_HASH succeeded."
fi


echo ""
echo "Done."
