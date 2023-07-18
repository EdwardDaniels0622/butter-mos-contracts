let {getMos} = require("../utils/helper.js")
const chainlist = [1,5,
    56, 97,  // bsc
    137, 80001, // matic
    212, 22776,  // mapo
    1001, 8217,  // klaytn
    "1360100178526209", "1360100178526210" // near
];


module.exports = async (taskArgs,hre) => {
    const accounts = await ethers.getSigners()
    const deployer = accounts[0];
    const chainId = await deployer.getChainId();
    console.log("deployer address:",deployer.address);

    let address = taskArgs.mos;
    if (address == "mos") {
        let proxy = await getMos(chainId,hre.network.name)
        if(!proxy) {
            throw "mos not deployed ..."
        }
        address = proxy.address;
    }
    console.log("mos address:\t", address);

    let mos = await ethers.getContractAt('MAPOmnichainServiceV2', address);

    let wtoken = await mos.wToken();
    let selfChainId = await mos.selfChainId();
    let relayContract = await mos.relayContract();
    let relayChainId = await mos.relayChainId();
    let lightNode = await mos.lightNode();

    console.log("selfChainId:\t", selfChainId.toString());
    console.log("wToken address:\t", wtoken);
    console.log("light node:\t", lightNode);
    console.log("relay chain:\t", relayChainId.toString());
    console.log("relay contract:\t", relayContract);

    address = taskArgs.token;
    if (address == "wtoken") {
        address = wtoken;
    }
    console.log("\ntoken address:", address);
    let mintable = await mos.isMintable(address);
    console.log(`token mintalbe:\t ${mintable}`);

    console.log("register chains:");
    for (let i = 0; i < chainlist.length; i++) {
        let bridgeable = await mos.isBridgeable(address, chainlist[i]);
        if (bridgeable) {
            console.log(`${chainlist[i]}`);
        }
    }

}