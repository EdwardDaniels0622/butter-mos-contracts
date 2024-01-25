# Butter Network MAPO Service

## Setup Instructions

Edit the .env-example.txt file and save it as .env

The following node and npm versions are required

```
$ node -v
v14.17.1
$ npm -v
6.14.13
```

Configuration file description

PRIVATE_KEY User-deployed private key

INFURA_KEY User-deployed infura key

SERVICE_IMPL_SALT Mos impl deploy salt

SERVICE_PROXY_SALT Mos proxy deploy salt

## Instruction

MAPOmnichainServiceV2 contract is suitable for evm-compatible chains and implements cross-chain logic

MAPOmnichainServiceRelayV2 contract implements cross-chain logic and basic cross-chain control based on MAP Relay Chain

TokenRegisterV2 contract is used to control the mapping of cross-chain tokens

## Build

```shell
git clone https://github.com/butternetwork/butter-mos-contracts
cd butter-mos-contracts/evmv2/
npm install
```

## Test

```shell
npx hardhat test
```

## Deploy

### MOS Relay

The following steps help to deploy MOS relay contracts on Map mainnet or Makalu testnet

1. Deploy Fee Center and Token Register

```
npx hardhat deploy --tags TokenRegisterV2 --network <network>
```

2. Deploy MOS Relay

```
npx hardhat relay:deploy --wrapped <wrapped token> --lightnode <lightNodeManager address> --network <network>
```

- `wrapped token` is wrapped MAP token address on MAP mainnet or MAP Makalu.
- `lightNodeManager address` is the light client mananger address deployed on MAP mainnet or MAP Makalu. See [here](../protocol/README.md) for more information.

3. Init MOS Relay (settype must be 'tokenregister' do not modify)

```
npx hardhat relay:setUp --settype tokenregister --address <token register address> --network <network>
```

4. set light client manager(if need change from deploy)

   ```
   npx hardhat relay:setUp --settype client --address <light client manager address> --network <network>
   ```
5. sets fee distribution

```
npx hardhat relay:setDistributeRate --type <0 to the token vault, 1 to specified receiver> --address <fee receiver address> --rate <rate 0-1000000, uni 0.000001> --network <network>
```

### MOS on EVM Chains

1. Deploy

```
npx hardhat mos:deploy --wrapped <native wrapped address> --lightnode <lightnode address> --network <network>
```

2. Set MOS Relay Address
   The following command on the EVM compatible chain

```
npx hardhat mos:setRelay --address <Relay address> --chain <map chainId> --network <network>
```

3. set light client(if need change from deploy)

   ```
   npx hardhat mos:setLightClient --address <light client manager address> --network <network>
   ```
4. Register
   The following command applies to the cross-chain contract configuration of Map mainnet and Makalu testnet

```
npx hardhat mos:setRelay  --address <MAPOmnichainService address> --chain <chain id> --network <network>
```

### MOS on other chain

The following four commands are generally applicable to Map mainnet and Makalu testnet

```
npx hardhat relay:registerChain --address <MAPOmnichainService address> --chain <near chain id> --type 2 --network <network>
```

**NOTE**: Near Protocol testnet chain id 5566818579631833089, mainnet chain id 5566818579631833088

## Configure

### Deploy Token

1. Deploy a mintable Token
   If want to transfer token through MOS, the token must exist on target chain. Please depoly the mapped mintable token on target chain if it does NOT exist.

```
npx hardhat tool:tokenDeploy --name <token name > --symbol <token symbol> --network <network>
```

2. Grant Mint Role to relay or mos contract

```
npx hardhat tool:tokenGrant --token <token address > --minter <adress/mos> --network <network>
```

### Register Token

1. Relay Chain deploy vault token
   Every token has a vault token. The vault token will distribute to the users that provide cross-chain liquidity.
   The mos relay contract is manager of all vault tokens.

```
npx hardhat tool:vaultDeploy --token <relaychain token address> --name <vault token name> --symbol <vault token symbol> --network <network>

npx hardhat tool:vaultAddManager --vault <vault token address> --manager <manager address> --network <network>
```

2. Register token

```
npx hardhat relay:registerToken --token <relaychain mapping token address> --vault <vault token address> --mintable <true/false> --network <network>
```

3. Set fee ratio to relay chain

```
npx hardhat relay:setTokenFee --token <token address> --chain <relay chain id>  --min <minimum fee value> --max <maximum fee value> --rate <fee rate 0-1000000> --network <network>
```

### Add Cross-chain Token

1. Relay Chain Bind the token mapping relationship between the two chains that requires cross-chain

```
npx hardhat relay:mapToken --token <relay chain token address> --chain <cross-chain id> --chaintoken <cross-chain token> --decimals <cross-chain token decimals> --network <network>
```

2. Relay Chain sets the token cross-chain fee ratio

```
npx hardhat relay:setTokenFee --token <token address> --chain <chain id>  --min <minimum fee value> --max <maximum fee value> --rate <fee rate 0-1000000> --network <network>
```

3. Altchain sets token mintable

```
npx hardhat service:setMintableToken --token <token address> --mintable <true/false> --network <network>
```

**NOTE:** If set the token mintable, the token must grant the minter role to mos contract.

4. Altchain sets bridge token

```
npx hardhat service:registerToken --token <token address> --chains < chain ids,separated by ',' > --network <network>
```

## Upgrade

When upgrade the mos contract through the following commands.

impl addOptionalParam if need redeploy the implement not need fill , else fill the implement address

update relay

```
npx hardhat relay:upgrade --impl <mos impl address> --network <network>
```

update mos on other evm chains

```
npx hardhat mos:upgrade --impl <mos impl address> --network <network>
```

## Token cross-chain deposit

1. token depsit

```
npx hardhat tool:depositOutToken --mos <mos address> --token <token address> --address <receiver address> --value <transfer value> --network <network>
```

Note that the --token parameter is optional, if not set, it means to transfer out Native Token.
Similarly --address is also an optional parameter. If it is not filled in, it will be the default caller's address.

transfer native token to other chain:

```
npx hardhat tool:depositOutToken --mos <mos or relay address>  --address <receiver address> --value <transfer value> --network <network>
```

## List token mapped chain

1. relay chain

```
npx hardhat relay:list --mos <relay address> --token <token address> --network <network>
```

2. altchains

```
npx hardhat service:list --mos <mos address> --token <token address> --network <network>
```
