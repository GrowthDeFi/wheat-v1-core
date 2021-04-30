require('dotenv').config();
const Web3 = require('web3');
const HDWalletProvider = require('@truffle/hdwallet-provider');

// process

function idle() {
  return new Promise((resolve, reject) => { });
}

function sleep(delay) {
  return new Promise((resolve, reject) => setTimeout(resolve, delay));
}

function abort(e) {
  console.error(e || new Error('Program aborted'));
  process.exit(1);
}

function exit() {
  process.exit(0);
}

function interrupt(f) {
  process.on('SIGINT', f);
  process.on('SIGTERM', f);
  process.on('SIGUSR1', f);
  process.on('SIGUSR2', f);
  process.on('uncaughtException', f);
  process.on('unhandledRejection', f);
}

function entrypoint(main) {
  const args = process.argv;
  (async () => { try { await main(args); } catch (e) { abort(e); } exit(); })();
}

function randomInt(limit) {
  return Math.floor(Math.random() * limit)
}

// web3

const privateKey = process.env['PRIVATE_KEY'] || '';
const ankrProjectId = process.env['ANKR_PROJECT_ID'] || '';
const ankrApikeyBscmain = process.env['ANKR_APIKEY_BSCMAIN'] || '';
const ankrApikeyBsctest = process.env['ANKR_APIKEY_BSCTEST'] || '';

const NETWORK_ID = {
  'bscmain': 56,
  'bsctest': 97,
};

const NETWORK_NAME = {
  56: 'bscmain',
  97: 'bsctest',
};

const ADDRESS_URL_PREFIX = {
  'bscmain': 'https://bscscan.com/address/',
  'bsctest': 'https://testnet.bscscan.com/address/',
};

const TX_URL_PREFIX = {
  'bscmain': 'https://bscscan.com/tx/',
  'bsctest': 'https://testnet.bscscan.com/tx/',
};

const NATIVE_SYMBOL = {
  'bscmain': 'BNB',
  'bsctest': 'BNB',
};

const HTTP_PROVIDER_URLS = {
  'bscmain': [
    'https://bsc-dataseed.binance.org/',
    'https://bsc-dataseed1.defibit.io/',
    'https://bsc-dataseed1.ninicoin.io/',
    'https://bsc-dataseed2.defibit.io/',
    'https://bsc-dataseed3.defibit.io/',
    'https://bsc-dataseed4.defibit.io/',
    'https://bsc-dataseed2.ninicoin.io/',
    'https://bsc-dataseed3.ninicoin.io/',
    'https://bsc-dataseed4.ninicoin.io/',
    'https://bsc-dataseed1.binance.org/',
    'https://bsc-dataseed2.binance.org/',
    'https://bsc-dataseed3.binance.org/',
    'https://bsc-dataseed4.binance.org/',
    'https://apis.ankr.com/' + ankrApikeyBscmain + '/' + ankrProjectId + '/binance/full/main',
  ],
  'bsctest': [
    'https://data-seed-prebsc-1-s1.binance.org:8545/',
    'https://data-seed-prebsc-2-s1.binance.org:8545/',
    'https://data-seed-prebsc-1-s2.binance.org:8545/',
    'https://data-seed-prebsc-2-s2.binance.org:8545/',
    'https://data-seed-prebsc-1-s3.binance.org:8545/',
    'https://data-seed-prebsc-2-s3.binance.org:8545/',
    'https://apis.ankr.com/' + ankrApikeyBsctest + '/' + ankrProjectId + '/binance/full/test',
  ],
};

const web3Cache = {};

function getWeb3(privateKey, network) {
  let web3 = web3Cache[network];
  if (!web3) {
    const index = randomInt(HTTP_PROVIDER_URLS[network].length);
    const url = HTTP_PROVIDER_URLS[network][index];
    const options = { transactionConfirmationBlocks: 0 };
    web3 = new Web3(new HDWalletProvider(privateKey, url), null, options);
    web3Cache[network] = web3;
  }
  return web3;
}

// lib

const IERC20_ABI = require('../build/contracts/ERC20.json').abi;
const MASTERCHEF_ABI = require('../build/contracts/CustomMasterChef.json').abi;
const PAIR_ABI = require('../build/contracts/Pair.json').abi;

const MASTERCHEF_ADDRESS = {
  'bscmain': '0x73feaa1eE314F8c655E354234017bE2193C9E24E',
  'bsctest': '0x7C83Cab4B208A0cD5a1b222D8e6f9099C8F37897',
};

async function main(args) {
  let [binary, script, network] = args;
  network = network || 'bscmain';

  const web3 = getWeb3(privateKey, network);
  const masterChef = new web3.eth.Contract(MASTERCHEF_ABI, MASTERCHEF_ADDRESS[network]);

  const length = await masterChef.methods.poolLength().call();
  console.log('Pools ' + length);

  for (let pid = 0; pid < length; pid++) {
    const { lpToken, allocPoint } = await masterChef.methods.poolInfo(pid).call();
    const pair = new web3.eth.Contract(PAIR_ABI, lpToken);

    let factory = null;
    try { factory = await pair.methods.factory().call(); } catch (e) { }

    let token0 = null;
    try { token0 = await pair.methods.token0().call(); } catch (e) { }

    let token1 = null;
    try { token1 = await pair.methods.token1().call(); } catch (e) { }

    let symbol0 = null;
    if (token0 !== null) {
      const contract = new web3.eth.Contract(IERC20_ABI, token0);
      try { symbol0 = await contract.methods.symbol().call(); } catch (e) { }
    }

    let symbol1 = null;
    if (token1 !== null) {
      const contract = new web3.eth.Contract(IERC20_ABI, token1);
      try { symbol1 = await contract.methods.symbol().call(); } catch (e) { }
    }

    let symbol = symbol0 + '/' + symbol1;
    if (symbol0 === null || symbol1 === null) {
      const contract = new web3.eth.Contract(IERC20_ABI, lpToken);
      try { symbol = await contract.methods.symbol().call(); } catch (e) { }
    }

    console.log('pid=' + pid + ' token=' + lpToken + ' points=' + allocPoint + ' factory=' + factory + ' ' + symbol);
  }
}

entrypoint(main);
