const { ethers, upgrades } = require("hardhat");
const { expect } = require("chai");
const { setUpAccessManagerToken } = require("./access-manager-setup");

async function deployContractsAndSetVariables(
  tokenSupply,
  transferFee,
  rentFee,
  allSignTC
) {
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
    await setUpAndDeployContracts(
      owner,
      custodian,
      facilitator,
      state_changer,
      tokenSupply,
      transferFee,
      rentFee
    );

  if (allSignTC)
    await signTermsAndConditions(remoratoken, custodian, [
      owner,
      investor1,
      investor2,
      investor3,
      investor4,
      custodian,
      facilitator,
      state_changer,
    ]);

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
  state_changer,
  tokenSupply,
  transferFee,
  rentFee
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
      allowlist.target,
      ausd.target,
      owner.address,
      rentFee, //10000, // fee, 10%
      transferFee,
      "Echo Apartments",
      "ECHO",
      tokenSupply, //10, //token supply
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

async function signTermsAndConditions(remoratoken, custodian, accounts) {
  for (let i = 0; i < accounts.length; ++i) {
    await remoratoken.connect(custodian).signTC(accounts[i].address);
    const tx = remoratoken.hasSignedTC(accounts[i].address);
    //console.log("value for ", accounts[i].address, " is ", tx);
    expect(await tx).to.be.true;
  }
}

module.exports = {
  deployContractsAndSetVariables,
};
