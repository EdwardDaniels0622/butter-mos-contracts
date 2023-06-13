set -e

SCRIPT_DIR=$(dirname $0)
source $SCRIPT_DIR/config.sh
FILE_NAME=$0

function printHelp() {
  echo "Usage:"
  echo "  $FILE_NAME <command>"
  echo "Commands:"
  echo "  list                                       view registered native tokens to chains"
  echo "  deposit  <from> <to> <amount>              deposit out native token"
  echo "  balance  <account>                         view account balance of native token"
  echo "  help                                       show help"
}

function list_to_chains() {
  echo "getting native token to chain list from mcs contract"
  near view $MCS_ACCOUNT get_native_token_to_chains '{}'
}

function deposit_out() {
  echo "deposit out $3 amount near from $1 to $2 on MAP chain"
  near call $MCS_ACCOUNT deposit_out_native '{ "to":'$2'}' --accountId $1 --depositYocto $3 --gas 100000000000000
}

function balance() {
  echo "get account $1 balance of near"
  near state $1
}

if [[ $# -gt 0 ]]; then
  case $1 in
    add)
      if [[ $# == 2 ]]; then
        add_to_chain $2
      else
        printHelp
        exit 1
      fi
      ;;
    remove)
      if [[ $# == 2 ]]; then
        remove_to_chain $2
      else
        printHelp
        exit 1
      fi
      ;;
    list)
      if [[ $# == 1 ]]; then
        list_to_chains
      else
        printHelp
        exit 1
      fi
      ;;
    deposit)
      if [[ $# == 4 ]]; then
        shift
        deposit_out $@
      else
        printHelp
        exit 1
      fi
      ;;
    balance)
      if [[ $# == 2 ]]; then
        balance $2
      else
        printHelp
        exit 1
      fi
      ;;
    help)
      printHelp
      ;;
    *)
      echo "Unknown command $1"
      printHelp
      exit 1
      ;;
  esac
  else
    printHelp
    exit 1
fi
