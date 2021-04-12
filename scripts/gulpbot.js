const fs = require('fs')
require('dotenv').config();
const axios = require('axios')
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

// conversion

function valid(amount, decimals) {
  const regex = new RegExp(`^\\d+${decimals > 0 ? `(\\.\\d{1,${decimals}})?` : ''}$`);
  return regex.test(amount);
}

function coins(units, decimals) {
  if (!valid(units, 0)) throw new Error('Invalid amount');
  if (decimals == 0) return units;
  const s = units.padStart(1 + decimals, '0');
  return s.slice(0, -decimals) + '.' + s.slice(-decimals);
}

function units(coins, decimals) {
  if (!valid(coins, decimals)) throw new Error('Invalid amount');
  let i = coins.indexOf('.');
  if (i < 0) i = coins.length;
  const s = coins.slice(i + 1);
  return coins.slice(0, i) + s + '0'.repeat(decimals - s.length);
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

function getWeb3(privateKey, network, index = 0) {
  let web3 = web3Cache[network];
  if (!web3) {
    const url = HTTP_PROVIDER_URLS[network][index];
    const options = { transactionConfirmationBlocks: 0 };
    web3 = new Web3(new HDWalletProvider(privateKey, url), null, options);
    web3Cache[network] = web3;
  }
  return web3;
}

// telegram

const telegramBotApiKey = process.env['TELEGRAM_BOT_API_KEY'] || '';
const telegramBotChatId = process.env['TELEGRAM_BOT_CHAT_ID'] || '';

let lastTelegramMessage = {};

async function sendTelegramMessage(message, key = '') {
  if (message !== lastTelegramMessage[key]) {
    console.log(new Date().toISOString());
    console.log(message);
    try {
      const url = 'https://api.telegram.org/bot'+ telegramBotApiKey +'/sendMessage';
      await axios.post(url, { chat_id: telegramBotChatId, text: message, parse_mode: 'HTML', disable_web_page_preview: true });
      lastTelegramMessage[key] = message;
    } catch (e) {
      console.error('FAILURE', e.message);
    }
  }
}

// lib

const IERC20_ABI = require('../build/contracts/IERC20.json').abi;
const MASTERCHEF_ABI = require('../build/contracts/CustomMasterChef.json').abi;
const STRATEGY_ABI = require('../build/contracts/RewardCompoundingStrategyToken.json').abi;
const COLLECTOR_ABI = require('../build/contracts/FeeCollector.json').abi;
const BUYBACK_ABI = require('../build/contracts/Buyback.json').abi;

const MASTERCHEF_ADDRESS = {
  'bscmain': '0x95fABAe2E9Fb0A269cE307550cAC3093A3cdB448',
  'bsctest': '0xF4748df5D63F6AB01e276065E6bD098Ce8dEA98a',
};

function getDefaultAccount(privateKey, network) {
  const web3 = getWeb3(privateKey, network);
  const [account] = web3.currentProvider.getAddresses();
  return account;
}

async function getNonce(privateKey, network, account = null) {
  const web3 = getWeb3(privateKey, network);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  const nonce = await web3.eth.getTransactionCount(account);
  return nonce;
}

async function getNativeBalance(privateKey, network, account = null) {
  const web3 = getWeb3(privateKey, network);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  const amount = await web3.eth.getBalance(account);
  return amount;
}

async function getTokenBalance(privateKey, network, address, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = IERC20_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  const amount = await contract.methods.balanceOf(account).call();
  return amount;
}

async function getTokenSymbol(privateKey, network, address) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const symbol = await contract.methods.symbol().call();
  return symbol;
}

async function pendingReward(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  const amount = await contract.methods.pendingReward().call();
  return amount;
}

async function pendingPerformanceFee(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  const amount = await contract.methods.pendingPerformanceFee().call();
  return amount;
}

async function getCollector(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  const collector = await contract.methods.collector().call();
  return collector;
}

async function pendingDeposit(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = COLLECTOR_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  const amount = await contract.methods.pendingDeposit().call();
  return amount;
}

async function getBuyback(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = COLLECTOR_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  const buyback = await contract.methods.buyback().call();
  return buyback;
}

async function pendingBuyback(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = BUYBACK_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  const amount = await contract.methods.pendingBuyback().call();
  return amount;
}

async function gulp(privateKey, network, address, nonce) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  await contract.methods.gulp().send({ from, nonce })
    .on('transactionHash', (hash) => {
      txId = hash;
    });
  if (txId === null) throw new Error('Failure reading txId');
  return txId;
}

async function poolLength(privateKey, network, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MASTERCHEF_ABI;
  const address = MASTERCHEF_ADDRESS[network];
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  const length = await contract.methods.poolLength().call();
  return length;
}

async function poolInfo(privateKey, network, pid, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MASTERCHEF_ABI;
  const address = MASTERCHEF_ADDRESS[network];
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  const { lpToken } = await contract.methods.poolInfo(pid).call();
  return { lpToken };
}

// app

const FIRST_PID = 5;
const MONITORING_INTERVAL = 15; // 15 seconds
const DEFAULT_GULP_INTERVAL = 12 * 60 * 60; // 12 hours
const GULP_INTERVAL = {
  // 5 - stkCAKE
  '0x84BA65DB2da175051E25F86e2f459C863CBb3E0C': 2 * 60 * 60, // 2 hours
  '0x14bAc5f216337F8da5f41Bb920514Af98ef62c36': 2 * 60 * 60, // 2 hours
  // 6 - stkBNB/CAKE
  '0xb290b079d7386C8e6F7a01F2f83c760aD807752C': 2 * 60 * 60, // 2 hours
  '0x84283A5eC825a68EFB0eb29C239dA2f4Fce6fdB0': 2 * 60 * 60, // 2 hours
  // 7 - stkBNB/BUSD
  '0x5cce1C68Db563586e10bc0B8Ef7b65265971cD91': 4 * 60 * 60, // 4 hours
  '0x250a57492741bC46FA33bE6d7EB816c3dE241008': 4 * 60 * 60, // 4 hours
  // 8 - stkBNB/BTCB
  '0x61f6Fa43D16890382E38E32Fd02C7601A271f133': 6 * 60 * 60, // 6 hours
  '0xC9E4479de5790C543F4d4D5CB9aF894454090c4a': 6 * 60 * 60, // 6 hours
  // 9 - stkBNB/ETH
  '0xc9e459BF16C10A40bc7daa4a2366ac685cEe784F': 6 * 60 * 60, // 6 hours
  '0x7B76FE59F0C438b8f43aD5D9B7C1d2033185e850': 6 * 60 * 60, // 6 hours
  // 10 - stkBNB/LINK
  '0xB2a97CC57AC2229a4017227cf71a28271a89f569': 12 * 60 * 60, // 12 hours
  '0x0e518bd0fa700a13C4aD4786CA355a770fd6391E': 12 * 60 * 60, // 12 hours
  // 11 - stkBNB/UNI
  '0x12821BE81Ee152DF53bEa1b9ad0B45A6d95B1ad5': 12 * 60 * 60, // 12 hours
  '0x610FB1D3738B068a6d032db2Bc32024AA3a3A827': 12 * 60 * 60, // 12 hours
  // 12 - stkBNB/DOT
  '0x9Be3593e1784E6Dc8A0b77760aA9e917Ed579676': 12 * 60 * 60, // 12 hours
  '0xFE92d2579c610d614e34fe975ebEF3812C525D36': 12 * 60 * 60, // 12 hours
  // 13 - stkBNB/ADA
  '0x13342abC6FD747dE2F11c58cB32f7326BE331183': 12 * 60 * 60, // 12 hours
  '0x833f43A57f9B785b4915af71Bc1144e2B043F602': 12 * 60 * 60, // 12 hours
  // 14 - stkBUSD/UST
  '0xd27F9D92cb456603FCCdcF2eBA92Db585140D969': 12 * 60 * 60, // 12 hours
  '0x35F23dd30f1F667C807732Be0De63dDFA4402478': 12 * 60 * 60, // 12 hours
  // 15 - stkBUSD/DAI
  '0xEe827483fb49a72C8c13C460275e39f7A59fB439': 12 * 60 * 60, // 12 hours
  '0x114EB5da8B4b5F8D7E37238CEF718eDb0C36a2Df': 12 * 60 * 60, // 12 hours
  // 16 - stkBUSD/USDC
  '0x97527E4033CAdD548eB2Eb5dB3BCdd8BF21f925D': 12 * 60 * 60, // 12 hours
  '0x9592F684C154B3Aa5F886453518f8739Fc1f8D5E': 12 * 60 * 60, // 12 hours
  // buyback
  '0xC351706C3212D45fc24F6B89e686f07fAb048b16': 6 * 60 * 60, // 12 hours
};

const strategyCache = {};

async function readStrategy(privateKey, network, pid) {
  if (strategyCache[pid]) return strategyCache[pid];
  const { lpToken: strategy } = await poolInfo(privateKey, network, pid);
  strategyCache[pid] = strategy;
  return strategy;
}

const collectorCache = {};

async function readCollector(privateKey, network, strategy) {
  if (collectorCache[strategy]) return collectorCache[strategy];
  const collector = await getCollector(privateKey, network, strategy);
  collectorCache[strategy] = collector;
  return collector;
}

const buybackCache = {};

async function readBuyback(privateKey, network, collector) {
  if (collectorCache[collector]) return collectorCache[collector];
  const buyback = await getBuyback(privateKey, network, collector);
  collectorCache[collector] = buyback;
  return buyback;
}

let lastGulp = {};

function readLastGulp() {
  try { lastGulp = JSON.parse(fs.readFileSync('gulpbot.json')); } catch (e) { }
}

function writeLastGulp() {
  try { fs.writeFileSync('gulpbot.json', JSON.stringify(lastGulp, undefined, 2)); } catch (e) { }
}

async function safeGulp(privateKey, network, address) {
  const now = Date.now();
  const timestamp = lastGulp[address] || 0;
  const ellapsed = (now - timestamp) / 1000;
  const interval = GULP_INTERVAL[address] || DEFAULT_GULP_INTERVAL;
  if (ellapsed < interval) return null;
  const nonce = await getNonce(privateKey, network);
  const txId = await gulp(privateKey, network, address, nonce);
  lastGulp[address] = now;
  writeLastGulp();
  return txId;
}

async function listContracts(privateKey, network) {
  const length = await poolLength(privateKey, network);
  console.log('pid', 'strategy', 'collector', 'buyback');
  for (let pid = FIRST_PID; pid < length; pid++) {
    const strategy = await readStrategy(privateKey, network, pid);
    const collector = await readCollector(privateKey, network, strategy);
    const buyback = await readBuyback(privateKey, network, collector);
    console.log(pid, strategy, collector, buyback);
  }
}

async function gulpAll(privateKey, network) {
  const length = await poolLength(privateKey, network);

  for (let pid = FIRST_PID; pid < length; pid++) {
    const strategy = await readStrategy(privateKey, network, pid);
    const [reward, fee] = await Promise.all([
      pendingReward(privateKey, network, strategy),
      pendingPerformanceFee(privateKey, network, strategy),
    ]);
    if (BigInt(reward) > 0n || BigInt(fee) > 0n) {
      const tx = await safeGulp(privateKey, network, strategy);
      if (tx !== null) {
        const symbol = await getTokenSymbol(privateKey, network, strategy);
        return { name: symbol, type: 'Strategy', address: strategy, tx };
      }
    }
  }

  for (let pid = FIRST_PID; pid < length; pid++) {
    const strategy = await readStrategy(privateKey, network, pid);
    const collector = await readCollector(privateKey, network, strategy);
    const [deposit, reward] = await Promise.all([
      pendingDeposit(privateKey, network, collector),
      pendingReward(privateKey, network, collector),
    ]);
    if (BigInt(deposit) > 0n || BigInt(reward) > 0n) {
      const tx = await safeGulp(privateKey, network, collector);
      if (tx !== null) {
        const symbol = await getTokenSymbol(privateKey, network, strategy);
        return { name: symbol, type: 'FeeCollector', address: collector, tx };
      }
    }
  }

  for (let pid = FIRST_PID; pid < length; pid++) {
    const strategy = await readStrategy(privateKey, network, pid);
    const collector = await readCollector(privateKey, network, strategy);
    const buyback = await readBuyback(privateKey, network, collector);
    const [reward] = await Promise.all([
      pendingBuyback(privateKey, network, buyback),
    ]);
    if (BigInt(reward) > 0n) {
      const tx = await safeGulp(privateKey, network, buyback);
      if (tx !== null) {
        const symbol = await getTokenSymbol(privateKey, network, strategy);
        return { name: symbol, type: 'Buyback', address: buyback, tx };
      }
    }
  }

  return false;
}

async function main(args) {
  let [binary, script, network] = args;
  network = network || 'bscmain';

  // handy to list all contracts
  // await listContracts(privateKey, network);
  // return;

  readLastGulp();

  await sendTelegramMessage('<i>GulpBot (' + network + ') Initiated</i>');

  let interrupted = false;
  interrupt(async (e) => {
    if (!interrupted) {
      interrupted = true;
      const message = e instanceof Error ? e.message : String(e);
      await sendTelegramMessage('<i>GulpBot (' + network + ') Interrupted (' + message + ')</i>');
      exit();
    }
  });
  while (true) {
    await sleep(MONITORING_INTERVAL * 1000);
    const lines = [];
    try {
      const account = getDefaultAccount(privateKey, network);
      const accountUrl = ADDRESS_URL_PREFIX[network] + account;
      const value = await getNativeBalance(privateKey, network);
      const balance = Number(coins(value, 18)).toFixed(4);
      lines.push('<a href="' + accountUrl + '">GulpBot</a>');
      lines.push('<code>' + balance + ' ' + NATIVE_SYMBOL[network] + '</code>');
      const result = await gulpAll(privateKey, network);
      if (result === false) continue;
      const { name, type, address, tx } = result;
      const url = ADDRESS_URL_PREFIX[network] + address;
      const txUrl = TX_URL_PREFIX[network] + tx;
      const txPrefix = tx.substr(0, 6);
      lines.push('<a href="' + url + '">' + type + '</a>.gulp() at <a href="' + txUrl + '">' + txPrefix + '</a> for ' + name);
    } catch (e) {
      console.error('error', e);
      lines.push('<i>GulpBot (' + network + ') Failure (' + e.message + ')</i>');
    }
    await sendTelegramMessage(lines.join('\n'));
  }
}

entrypoint(main);
