const { ethers, upgrades } = require("hardhat");
const { setUpAccessManagerToken } = require("./AccessManagerSetUp");

async function deployContractsAndSetVariables() {
  const [
    owner,
    investor1,
    investor2,
    investor3,
    investor4,
    custodian,
    facilitator,
    state_changer,
  ] = await ethers.getSigners();

  const { remoratoken, allowlist, ausd, accessmanager } =
    await setUpAndDeployContracts(owner, custodian, facilitator, state_changer);

  return {
    owner,
    investor1,
    investor2,
    investor3,
    investor4,
    custodian,
    facilitator,
    state_changer,
    remoratoken,
    allowlist,
    ausd,
    accessmanager,
  };
}

async function setUpAndDeployContracts(
  owner,
  custodian,
  facilitator,
  state_changer
) {
  //set up stablecoin
  const AUSD = await ethers.getContractFactory("Stablecoin");
  const ausd = await AUSD.deploy("AUSD", "AUSD", 10000000000);

  //set up access manager
  const AccessManager = await ethers.getContractFactory("RemoraManager");
  const accessmanager = await upgrades.deployProxy(
    AccessManager,
    [owner.address],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );
  await accessmanager.waitForDeployment();

  //set up allowlist
  const RemoraAllowList = await ethers.getContractFactory("RemoraAllowlist");
  const allowlist = await upgrades.deployProxy(
    RemoraAllowList,
    [accessmanager.target, owner.address],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );
  await allowlist.waitForDeployment();

  //set up remora token
  const RemoraToken = await ethers.getContractFactory("RemoraRWAToken");
  const remoratoken = await upgrades.deployProxy(
    RemoraToken,
    [
      owner.address,
      accessmanager.target,
      "Echo Apartments",
      "ECHO",
      10, //token supply
      allowlist.target,
      ausd.target,
      owner.address,
      10000, // fee, 10%
    ],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );
  await remoratoken.waitForDeployment();

  await setUpAccessManagerToken(
    accessmanager,
    custodian,
    facilitator,
    state_changer,
    remoratoken,
    allowlist
  );

  return { remoratoken, allowlist, ausd, accessmanager };
}

module.exports = {
  deployContractsAndSetVariables,
};
