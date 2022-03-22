const Svn = artifacts.require("SavannaToken");
const MShare = artifacts.require("MShare");
const MBond = artifacts.require("MBond");
const MockedSvn = artifacts.require("MockedSvn");
const MockedMShare = artifacts.require("MockedMShare");
const MockedMMF = artifacts.require("MeerkatToken");

module.exports = async (deployer, network, [account]) => {
  const COMMUNITY_FUND = "" || account;
  const DEV_FUND = "" || account;
  const TREASURY_FUND = "" || account;

  const Svn_TAX_RATE = 0;

  const MShare_START_TIME = "0";

  const SvnContract = network == "mainnet" ? Svn : MockedSvn;
  const MShareContract = network == "mainnet" ? MShare : MockedMShare;

  // Svn contract
  await deployer.deploy(SvnContract, Svn_TAX_RATE, COMMUNITY_FUND);

  // MShare contract
  await deployer.deploy(
    MShareContract,
    MShare_START_TIME,
    COMMUNITY_FUND,
    DEV_FUND,
    TREASURY_FUND
  );

  // MBond contract
  await deployer.deploy(MBond);

  await deployer.deploy(MockedMMF);
};
