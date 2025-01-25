const { ethers, upgrades } = require("hardhat");
const { setUpAccessManagerToken } = require("./AccessManagerSetUp");

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
      1000, //token supply
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
  setUpAndDeployContracts,
};
