#!/usr/bin/env bash

while getopts r:n:p: flag
do
    case "${flag}" in
        r) REGISTRAR_ADDRESS=${OPTARG};;
        n) NETWORK=${OPTARG};;
        p) ADDRESS_PATH=${OPTARG};;
    esac
done

echo "REGISTRAR_ADDRESS=$REGISTRAR_ADDRESS";
echo "NETWORK=$NETWORK";
echo "ADDRESS_PATH=$ADDRESS_PATH";

if [ -z "$REGISTRAR_ADDRESS"] || [ -z "$NETWORK" ] || [ -z "$ADDRESS_PATH" ];
then
  echo 'MISSING REQUIRED VARIABLES';
  exit 1;
fi

if [[ ! -f "$ADDRESS_PATH" ]]
then
  echo "{}" > $ADDRESS_PATH;
fi

npx hardhat compile;
npx hardhat deployZPM --network $NETWORK --registrar-address $REGISTRAR_ADDRESS;
npx hardhat deployZMAM --network $NETWORK;
npx hardhat deployTransferHelper --network $NETWORK --transfer-type ERC20;
npx hardhat deployTransferHelper --network $NETWORK --transfer-type ERC721;

exit 0;