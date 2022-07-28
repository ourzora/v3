#!/usr/bin/env python3

# must be run from root folder, not from inside deploy

import sys, json
from os.path import exists

if __name__ == '__main__':
    num_args = len(sys.argv)
    if num_args % 2 != 0 or num_args < 4:
        raise Exception('args must be chainid followed by pairs of contract name, contract address')
    chain_id = sys.argv[1]
    file_path = 'addresses/' + chain_id + '.json'
    file_exists = exists(file_path)
    addrs_dict = {}
    if (file_exists):
        with open(file_path) as f:
            addrs_dict = json.load(f)
    for i in list(range(2, num_args, 2)):
        addrs_dict[sys.argv[i]] = sys.argv[i+1]
    with open(file_path, "w") as write_file:
        json.dump(addrs_dict, write_file, indent=2, sort_keys=True)
        write_file.write("\n")
