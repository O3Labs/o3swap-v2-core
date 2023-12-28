import * as hre from "hardhat";
import { BigNumber } from "bignumber.js";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { REPLServer } from "repl";

declare var global: any;
let repl: REPLServer;

/*

Available utility variable/functions:
    variables:
        me: the account0, usually set from `.private_key`.
        ONE: BigNumber('1e18').

    functions:
        e{n}(value): make number readable, e.g. e18(await token.balanceOf(address)).
        balance(): print native balance of account0.

*/

let me: SignerWithAddress;

export {
    loadBaseUtils,
    confirmDeploy,
    init,
    deployImpl,
    me,
    contractName,
    instanceName,
};

var deployed: { [key: string]: string } = {}
var contractName = '';
var instanceName = '';
var deployFunc: Function;

async function load(contract: string) {
    const instance = await hre.ethers.getContractAt(contractName, contract);
    global[instanceName] = instance
    console.log(`use '${instanceName}' to access the deployed contract instance`);
}

async function init(
    _deployed: { [key: string]: string },
    _contractName: string,
    _instanceName: string,
    _deployFunc: Function,
) {
    deployed = _deployed;
    contractName = _contractName;
    instanceName = _instanceName;
    deployFunc = _deployFunc;

    await loadBaseUtils();
    await loadDeployed();
}

async function loadBaseUtils() {
    await loadVariables();
    await loadFunctions();

    console.log(`current chain is ${hre.network.name}, chainID = ${hre.network.config.chainId}`);

    const { addr, balance } = await getGlobalAssetBalance();
    console.log(`current signer is ${addr}, native asset balance = ${balance}`);

    repl = require("repl").start();
    global = repl.context;

    global.load = load;
    global.deploy = deployFunc;
}

async function loadDeployed() {
    const networkName = hre.network.name;

    if (networkName in deployed && deployed[networkName] != '') {
        const contractAddr = deployed[networkName];
        const instance = await hre.ethers.getContractAt(contractName, contractAddr)
        global[instanceName] = instance
        console.log(`use '${instanceName}' to access the deployed contract instance`);
    }
}

async function deployImpl(instance: any) {
    if (contractName == '' || instanceName == '') {
        console.log('`contractName` and `instanceName` must be set before deploy');
        return;
    }

    console.log(`deploy ${contractName}`);

    await confirmDeploy();
    await instance.deployed();
    global[instanceName] = instance

    console.log(`${contractName} deployed to ${hre.network.name} at ${instance.address}`);
    console.log(`use '${instanceName}' to access the deployed contract instance`);

    return instance.address;
}

async function loadVariables() {
    me = await getAccount0();
    global.me = me;
    global.ONE = require('bignumber.js').BigNumber('1e18');
}

async function loadFunctions() {
    genExFunc();
    genBalanceFunc();
}

async function getAccount0() {
    var accounts = (await hre.ethers.getSigners());
    return accounts[0];
}

function genBalanceFunc() {
    (global as any)['balance'] = async () => {
        const { addr, balance } = await getGlobalAssetBalance();

        console.log(`${addr} native asset balance: ${balance}`);
    }
}

function genExFunc() {
    for (let i = 0; i <= 18; i++) {
        (global as any)[`e${i}`] = (val: any) => {
            let readable = (new BigNumber(val.toString())).shiftedBy(-i).toFixed();
            console.log(readable);
        }
    }
}

async function getGlobalAssetBalance() {
    let rawBalance = await me.getBalance();
    let readable = (new BigNumber(rawBalance.toString())).shiftedBy(-18).toFixed();

    return {
        addr: me.address,
        balance: readable
    };
}

async function getGasPrice() {
    var gasPrice = hre.config.networks[hre.network.name].gasPrice;
    if (gasPrice == "auto") {
        gasPrice = (await hre.ethers.provider.getGasPrice()).toNumber();
        return gasPrice / 1e9 + "(auto)";
    }

    return gasPrice / 1e9 + "(fixed)";
}

async function confirmDeploy() {
    console.log(`current gasPrice = ${await getGasPrice()}`);
    process.stdout.write("press enter to confirm deploy, otherwise exit");
    await waitKeyPressed();
    console.log();
}

function waitKeyPressed() {
    return new Promise(resolve => {
        const wasRaw = process.stdin.isRaw;
        process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.once("data", (data) => {
            if (!data.equals(Buffer.from([0x0d]))) {
                process.exit();
            }

            process.stdin.setRawMode(wasRaw);
            resolve(data.toString());
        });
    });
}
