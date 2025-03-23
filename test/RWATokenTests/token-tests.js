const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  deployContractsAndSetVariables,
} = require("../helpers/setup-contracts");
const { expect } = require("chai");

describe("RemoraRWAToken Tests", function () {
  async function setUpRemoraRWATests() {
    return await deployContractsAndSetVariables(10, 0, 0, 0, true);
  }

  async function setUpRemoraRWATestsNS() {
    // Not signing TC
    return await deployContractsAndSetVariables(10, 0, 0, 0, false);
  }

  it("Should block transfer token with fee", async function () {
    const { investor1, investor2, custodian, remoratoken, ausd, allowlist } =
      await loadFixture(setUpRemoraRWATests);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await allowlist.connect(custodian).allowUser(investor2.address);
    await remoratoken.transfer(investor1.address, 10);
    await remoratoken.connect(custodian).setTransferFee(500);

    await expect(
      remoratoken.connect(investor1).transfer(investor2.address, 10)
    ).to.be.revertedWithCustomError(ausd, "ERC20InsufficientAllowance");
  });

  it("Should successfully transfer tokens with fee", async function () {
    const {
      owner,
      investor1,
      investor2,
      custodian,
      remoratoken,
      ausd,
      allowlist,
    } = await loadFixture(setUpRemoraRWATests);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await allowlist.connect(custodian).allowUser(investor2.address);
    await remoratoken.transfer(investor1.address, 10);
    await ausd.transfer(investor1, 500);
    await remoratoken.connect(custodian).setTransferFee(500);

    await ausd.connect(investor1).approve(remoratoken.target, 500);

    const tx = remoratoken.connect(investor1).transfer(investor2.address, 10);
    await expect(tx).to.changeTokenBalances(
      remoratoken,
      [investor1, investor2],
      [-10, +10]
    );

    await expect(tx).to.changeTokenBalances(
      ausd,
      [investor1, owner],
      [-500, +500]
    );
  });

  it("Should pause halting transfer, then unpause", async function () {
    const {
      owner,
      investor1,
      custodian,
      state_changer,
      remoratoken,
      allowlist,
    } = await loadFixture(setUpRemoraRWATests);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await remoratoken.transfer(investor1.address, 10);

    await remoratoken.connect(state_changer).pause();

    await expect(
      remoratoken.connect(investor1).transfer(owner.address, 10)
    ).to.be.revertedWithCustomError(remoratoken, "EnforcedPause");

    await remoratoken.connect(state_changer).unpause();

    await expect(
      remoratoken.connect(investor1).transfer(owner.address, 10)
    ).to.changeTokenBalances(remoratoken, [investor1, owner], [-10, +10]);
  });

  it("Should revert transfer due to no approval of transfer fee, then should work after approval (transfer)", async function () {
    const {
      owner,
      investor1,
      investor2,
      custodian,
      remoratoken,
      allowlist,
      ausd,
    } = await loadFixture(setUpRemoraRWATests);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await allowlist.connect(custodian).allowUser(investor2.address);
    await ausd.transfer(investor1.address, 50000);
    await remoratoken.transfer(investor1.address, 10);

    await remoratoken.connect(custodian).setTransferFee(50000); // 5 cents

    await expect(
      remoratoken.connect(investor1).transfer(investor2.address, 5)
    ).to.be.revertedWithCustomError(ausd, "ERC20InsufficientAllowance");

    await ausd.connect(investor1).approve(remoratoken.target, 50000);

    const tx = remoratoken.connect(investor1).transfer(investor2.address, 5);
    await expect(tx).to.changeTokenBalances(
      remoratoken,
      [investor1, investor2],
      [-5, +5]
    );

    await expect(tx).to.changeTokenBalances(
      ausd,
      [owner, investor1],
      [+50000, -50000]
    );
  });

  it("Should revert transfer due to no approval of transfer fee, then should work after approval (transferFrom)", async function () {
    const {
      owner,
      investor1,
      investor2,
      investor3,
      custodian,
      remoratoken,
      allowlist,
      ausd,
    } = await loadFixture(setUpRemoraRWATests);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await allowlist.connect(custodian).allowUser(investor2.address);
    await ausd.transfer(investor3.address, 50000);
    await remoratoken.transfer(investor1.address, 10);
    await remoratoken.connect(investor1).approve(investor3.address, 5);

    await remoratoken.connect(custodian).setTransferFee(50000); // 5 cents

    await expect(
      remoratoken
        .connect(investor3)
        .transferFrom(investor1.address, investor2.address, 5)
    ).to.be.revertedWithCustomError(ausd, "ERC20InsufficientAllowance");

    await ausd.connect(investor3).approve(remoratoken.target, 50000);

    const tx = remoratoken
      .connect(investor3)
      .transferFrom(investor1.address, investor2.address, 5);

    await expect(tx).to.changeTokenBalances(
      remoratoken,
      [investor1, investor2],
      [-5, +5]
    );

    await expect(tx).to.changeTokenBalances(
      ausd,
      [owner, investor3],
      [+50000, -50000]
    );
  });

  it("Should revert due to transfer to unregistered user, then allow after registering", async function () {
    const { owner, investor1, custodian, remoratoken, allowlist } =
      await loadFixture(setUpRemoraRWATests);

    await expect(
      remoratoken.transfer(investor1.address, 10)
    ).to.be.revertedWithCustomError(allowlist, "UserNotRegistered");

    await allowlist.connect(custodian).allowUser(investor1.address);

    await expect(
      remoratoken.transfer(investor1.address, 10)
    ).to.changeTokenBalances(remoratoken, [investor1, owner], [+10, -10]);
  });

  it("Should revert due to restricted transfer", async function () {
    const { owner, investor1, custodian, remoratoken, allowlist } =
      await loadFixture(setUpRemoraRWATests);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await expect(
      remoratoken.adminTransferFrom(
        owner.address,
        investor1.address,
        10,
        true,
        false
      )
    ).to.be.revertedWithCustomError(remoratoken, "AccessManagedUnauthorized");
  });

  it("Should successfully transfer tokens without fee and without signing TC (whitelist)", async function () {
    const { owner, investor1, custodian, remoratoken, allowlist } =
      await loadFixture(setUpRemoraRWATestsNS);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await remoratoken.connect(custodian).signTC(owner.address);

    expect(await remoratoken.hasSignedTC(investor1)).to.be.false;

    await expect(
      remoratoken.transfer(investor1.address, 5)
    ).to.be.revertedWithCustomError(remoratoken, "TermsAndConditionsNotSigned");

    await remoratoken.connect(custodian).addToWhitelist(investor1.address);
    await remoratoken.connect(custodian).setTransferFee(500);

    await expect(
      remoratoken.transfer(investor1.address, 5)
    ).to.changeTokenBalances(remoratoken, [owner, investor1], [-5, +5]);
  });

  // it("Should successfully upgrade RWAToken and Allowlist", async function () {
  //   const {
  //     owner,
  //     accessmanager,
  //     investor1,
  //     investor2,
  //     custodian,
  //     remoratoken,
  //     allowlist,
  //   } = await loadFixture(setUpRemoraRWATests);

  //   await allowlist.connect(custodian).allowUser(investor1.address);
  //   await remoratoken.transfer(investor1.address, 5);

  //   const RemoraAllowListV2 = await ethers.getContractFactory(
  //     "RemoraAllowlistV2"
  //   );

  //   await expect(
  //     upgrades.upgradeProxy(allowlist.target, RemoraAllowListV2)
  //   ).to.be.revertedWithCustomError(allowlist, "AccessManagedUnauthorized");

  //   await accessmanager.grantRole(CUSTODIAN_ID, owner, 0); // grant role to owner so can upgrade

  //   const allowlistV2 = await upgrades.upgradeProxy(
  //     allowlist.target,
  //     RemoraAllowListV2
  //   );

  //   expect(await allowlistV2.version()).to.equal(2);

  //   const RemoraRWATokenV2 = await ethers.getContractFactory(
  //     "RemoraRWATokenV2"
  //   );
  //   const remoratokenV2 = await upgrades.upgradeProxy(
  //     remoratoken.target,
  //     RemoraRWATokenV2
  //   );

  //   expect(await remoratokenV2.version()).to.equal(2);

  //   await expect(
  //     remoratokenV2.transfer(investor2.address, 5)
  //   ).to.be.revertedWithCustomError(allowlistV2, "UserNotRegistered");

  //   await expect(
  //     remoratokenV2.transfer(investor1.address, 5)
  //   ).to.changeTokenBalances(remoratokenV2, [owner, investor1], [-5, +5]);
  // });
});
