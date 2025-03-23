const { ethers } = require("hardhat");

const CUSTODIAN_ID = 1;
const FACILITATOR_ID = 2;
const STATE_CHANGER_ID = 3;
const INTERMEDIARY_ID = 4;

function getSelector(signature) {
  return ethers.id(signature).slice(0, 10);
}

async function setUpAccessManagerToken(
  accessManager,
  custodian,
  facilitator,
  state_changer,
  remoraToken,
  allowlist
) {
  //sets up two roles by default
  await accessManager.labelRole(CUSTODIAN_ID, "CUSTODIAN"); //manages upgrades, freezing, allowing users
  await accessManager.labelRole(FACILITATOR_ID, "FACILITATOR"); //manages transfers, and adminClaimRent
  await accessManager.labelRole(STATE_CHANGER_ID, "STATE_CHANGER"); //manages pausing and burning

  const custodian_selectors = [
    // add delay in real use
    getSelector("mint(address,uint256)"),
    getSelector("upgradeToAndCall(address,bytes)"),
    getSelector("updateAllowList(address)"),
    getSelector("setPayoutFee(uint32)"),
    getSelector("setTransferFee(uint32)"),
    getSelector("changeStablecoin(address)"),
    getSelector("changeWallet(address)"),
    getSelector("freezeHolder(address)"),
    getSelector("unFreezeHolder(address)"),
    getSelector("withdraw(bool,uint256)"),
    getSelector("signTC(address)"),
    getSelector("addToWhitelist(address)"),
    getSelector("removeFromWhitelist(address)"),
    getSelector("setPayoutForwardAddress(address,address)"),
    getSelector("setLockUpTime(uint32)"),
    getSelector("removePayoutForwardAddress(address)"),
  ];

  const custodian_allowlist_selectors = [
    getSelector("upgradeToAndCall(address,bytes)"),
    getSelector("allowUser(address)"),
    getSelector("disallowUser(address)"),
  ];

  const facilitator_selectors = [
    getSelector("distributePayout(uint128)"),
    getSelector("adminClaimPayout(address,bool,bool,uint256)"),
    getSelector("adminTransferFrom(address,address,uint256,bool,bool)"),
    getSelector(
      "payoutAll((bool,bool,address,address,uint32,uint128,address[]))"
    ),
    getSelector("burnFrom(address,uint256)"),
  ];

  const state_selectors = [
    getSelector("pause()"),
    getSelector("unpause()"),
    getSelector("enableBurning(bool,uint64)"),
    getSelector("disableBurning()"),
  ];

  //set up roles for RWAToken
  await accessManager.setTargetFunctionRole(
    remoraToken.target,
    custodian_selectors,
    CUSTODIAN_ID
  );

  await accessManager.setTargetFunctionRole(
    remoraToken.target,
    facilitator_selectors,
    FACILITATOR_ID
  );

  await accessManager.setTargetFunctionRole(
    remoraToken.target,
    state_selectors,
    STATE_CHANGER_ID
  );

  //set up role for allowlist
  await accessManager.setTargetFunctionRole(
    allowlist.target,
    custodian_allowlist_selectors,
    CUSTODIAN_ID
  );

  await accessManager.grantRole(CUSTODIAN_ID, custodian, 0);
  await accessManager.grantRole(FACILITATOR_ID, facilitator, 0);
  await accessManager.grantRole(STATE_CHANGER_ID, state_changer, 0);
}

async function setUpAccessManagerIntermediary( // only call after setting up token
  accessManager,
  remoratoken,
  custodian,
  intermediary,
  facilitator
) {
  const intermediary_selectors = [
    getSelector("adminTransferFrom(address,address,uint256,bool,bool)"),
    getSelector("adminClaimPayout(address,bool,bool,uint256)"),
  ];

  const custodian_selectors = [
    getSelector("setFeeRecipient(address)"),
    getSelector("setFundingWallet(address)"),
  ];

  const facilitator_selectors = [
    getSelector(
      "swapTokens((address,address,address,address,address,bool,uint32,uint128,uint128))"
    ),
    getSelector(
      "processRwaSale((address,address,address,address,address,bool,uint32,uint128,uint128))"
    ),
    getSelector("processPayout((address,address,address,bool,uint32,uint128))"),
    getSelector(
      "payoutAll((bool,bool,address,address,uint32,uint128,address[]))"
    ),
  ];

  await accessManager.setTargetFunctionRole(
    remoratoken.target,
    intermediary_selectors,
    INTERMEDIARY_ID
  );

  await accessManager.setTargetFunctionRole(
    intermediary.target,
    facilitator_selectors,
    FACILITATOR_ID
  );

  await accessManager.setTargetFunctionRole(
    intermediary.target,
    custodian_selectors,
    CUSTODIAN_ID
  );

  await accessManager.grantRole(CUSTODIAN_ID, custodian, 0);
  await accessManager.grantRole(INTERMEDIARY_ID, intermediary.target, 0);
  await accessManager.grantRole(FACILITATOR_ID, facilitator, 0);
}

async function allowUsers(custodian, allowlist, investors) {
  for (const investor of investors) {
    await allowlist.connect(custodian).allowUser(investor.address);
  }
}

module.exports = {
  CUSTODIAN_ID,
  FACILITATOR_ID,
  STATE_CHANGER_ID,
  getSelector,
  setUpAccessManagerToken,
  setUpAccessManagerIntermediary,
  allowUsers,
};
