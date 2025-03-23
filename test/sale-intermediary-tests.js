const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployContractsAndSetVariables } = require("./helpers/setup-contracts");
const {
  setUpAccessManagerToken,
  setUpAccessManagerIntermediary,
} = require("./helpers/access-manager-setup");
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Sale Intermediary Tests", function () {
  async function setUpSaleIntermediaryTests() {
    const {
      owner,
      investor1,
      investor2,
      custodian,
      facilitator,
      state_changer,
      remoratoken,
      allowlist,
      ausd,
      accessmanager,
    } = await deployContractsAndSetVariables(10, 50, 10000, 0, true);
    //token supply: 10
    //transfer fee: 50 = 50 cents (not doing up to 6 decimals in this test)
    //rent fee: 10%

    const SaleIntermediary = await ethers.getContractFactory(
      "RemoraSaleIntermediary"
    );
    const saleIntermediary = await SaleIntermediary.deploy(
      accessmanager.target,
      owner.address,
      owner.address
    );
    await saleIntermediary.waitForDeployment();

    const RMRACoin = await ethers.getContractFactory("RMRA");
    const rmra = await RMRACoin.deploy("Remora Coin", "RMRA", 10000);

    await setUpAccessManagerIntermediary(
      accessmanager,
      remoratoken,
      custodian,
      saleIntermediary,
      facilitator
    );

    await ausd.transfer(investor1.address, 1000);

    return {
      owner,
      investor1,
      investor2,
      custodian,
      facilitator,
      state_changer,
      remoratoken,
      allowlist,
      ausd,
      rmra,
      accessmanager,
      saleIntermediary,
    };
  }

  async function setUpSaleIntermediaryPayoutTests() {
    const {
      owner,
      investor1,
      investor2,
      custodian,
      facilitator,
      state_changer,
      remoratoken,
      allowlist,
      ausd,
      rmra,
      accessmanager,
      saleIntermediary,
    } = await setUpSaleIntermediaryTests();

    const RemoraToken = await ethers.getContractFactory("RemoraRWAToken");
    const remoratoken2 = await upgrades.deployProxy(
      RemoraToken,
      [
        owner.address,
        accessmanager.target,
        allowlist.target,
        ausd.target,
        owner.address,
        "888 Apartments",
        "888a",
        10,
      ],
      {
        initializer: "initialize",
        kind: "uups",
      }
    );
    await remoratoken2.waitForDeployment();

    await setUpAccessManagerToken(
      accessmanager,
      custodian,
      facilitator,
      state_changer,
      remoratoken2,
      allowlist
    );

    await setUpAccessManagerIntermediary(
      accessmanager,
      remoratoken2,
      custodian,
      saleIntermediary,
      facilitator
    );

    await remoratoken2.connect(custodian).signTC(owner.address);
    await remoratoken2.connect(custodian).signTC(investor1.address);
    await remoratoken2.connect(custodian).setPayoutFee(10000);

    return {
      owner,
      investor1,
      investor2,
      custodian,
      facilitator,
      state_changer,
      remoratoken,
      allowlist,
      ausd,
      rmra,
      accessmanager,
      saleIntermediary,
      remoratoken2,
    };
  }

  describe("processRwaSale Tests", function () {
    it("Should revert due to insufficient allowed balance from buyer", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      //need to add user to allowlist to allow token trade
      await allowlist.connect(custodian).allowUser(investor1.address);

      //make only one approval
      await remoratoken.approve(saleIntermediary.target, 10);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: false,
        feeAmount: 0,
        feeToken: ausd.target,
      };

      await expect(
        saleIntermediary.connect(facilitator).processRwaSale(
          // 1000 tokens of ausd for 10 remoratokens
          tradeData
        )
      ).to.be.revertedWithCustomError(ausd, "ERC20InsufficientAllowance");
    });

    it("Should revert due to insufficient allowed balance from seller", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      //need to add user to allowlist to allow token trade
      await allowlist.connect(custodian).allowUser(investor1.address);

      //make only one approval
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: false,
        feeAmount: 0,
        feeToken: ausd.target,
      };

      await expect(
        saleIntermediary.connect(facilitator).processRwaSale(
          // 1000 tokens of ausd for 10 remoratokens
          tradeData
        )
      ).to.be.revertedWithCustomError(
        remoratoken,
        "ERC20InsufficientAllowance"
      );
    });

    it("Should revert due to call from unauthorized account", async function () {
      const {
        owner,
        investor1,
        custodian,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      await allowlist.connect(custodian).allowUser(investor1.address);

      //make proper approvals
      await remoratoken.approve(saleIntermediary.target, 10);
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: false,
        feeAmount: 0,
        feeToken: ausd.target,
      };

      await expect(
        saleIntermediary.processRwaSale(
          // 1000 tokens of ausd for 10 remoratokens
          tradeData
        )
      ).to.be.revertedWithCustomError(
        saleIntermediary,
        "AccessManagedUnauthorized"
      );
    });

    it("Should revert transfer due to no fee approval", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await saleIntermediary
        .connect(custodian)
        .setFeeRecipient(custodian.address);

      //make proper approvals, except fee approval
      await remoratoken.approve(saleIntermediary.target, 10);
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: true,
        feeAmount: 100,
        feeToken: ausd.target,
      };

      await expect(
        saleIntermediary.connect(facilitator).processRwaSale(
          // 1000 tokens of ausd for 10 remoratokens
          tradeData
        )
      ).to.be.revertedWithCustomError(ausd, "ERC20InsufficientAllowance");
    });

    it("Should successfully transfer remoratoken for ausd, with fee collected", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await saleIntermediary
        .connect(custodian)
        .setFeeRecipient(custodian.address);

      //make proper approvals
      await remoratoken.approve(saleIntermediary.target, 10);
      await ausd.approve(saleIntermediary.target, 100);
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: true,
        feeAmount: 100,
        feeToken: ausd.target,
      };

      const tx = saleIntermediary.connect(facilitator).processRwaSale(
        // 1000 tokens of ausd for 10 remoratokens
        tradeData
      );

      await expect(tx).to.changeTokenBalances(
        remoratoken,
        [investor1, owner],
        [+10, -10]
      );
      await expect(tx).to.changeTokenBalances(
        ausd,
        [investor1, owner, custodian],
        [-1000, +900, +100]
      );
    });

    it("Should successfully transfer remoratoken for ausd, with no fee collected", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      await allowlist.connect(custodian).allowUser(investor1.address);

      //make proper approvals
      await remoratoken.approve(saleIntermediary.target, 10);
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: false,
        feeAmount: 0,
        feeToken: ausd.target,
      };

      const tx = saleIntermediary.connect(facilitator).processRwaSale(
        // 1000 tokens of ausd for 10 remoratokens
        tradeData
      );

      await expect(tx).to.changeTokenBalances(
        remoratoken,
        [investor1, owner],
        [+10, -10]
      );
      await expect(tx).to.changeTokenBalances(
        ausd,
        [investor1, owner],
        [-1000, +1000]
      );
    });
  });

  describe("Claim Payout Tests", function () {
    it("Should allow claim of all tokens a user owns in stablecoin", async function () {
      const {
        owner,
        investor1,
        remoratoken,
        remoratoken2,
        custodian,
        facilitator,
        allowlist,
        ausd,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryPayoutTests);
      //send stablecoin to payout contract ($1000)
      await ausd.transfer(remoratoken.target, 1000000000);
      await ausd.transfer(remoratoken2.target, 1000000000);

      await allowlist.connect(custodian).allowUser(owner);
      await allowlist.connect(custodian).allowUser(investor1);

      await remoratoken.transfer(investor1.address, 5); //out of 10 tokens
      await remoratoken2.transfer(investor1.address, 5); // out of 10

      //distribute $1000
      // 10 cent fee
      await remoratoken.connect(facilitator).distributePayout(1000000000);
      await remoratoken2.connect(facilitator).distributePayout(1000000000);

      const rwaAddrs = [remoratoken.target, remoratoken2.target];
      const payoutStruct = {
        useStablecoin: true,
        useCustomFee: false,
        holder: investor1.address,
        paymentToken: ethers.ZeroAddress,
        feeValue: 0,
        amount: 0,
        rwaTokens: rwaAddrs,
      };

      10000;
      const tx = saleIntermediary.connect(facilitator).payoutAll(payoutStruct);
      await expect(await tx).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-499990000, +999980000]
      );
      await expect(await tx).to.changeTokenBalances(
        ausd,
        [remoratoken2, investor1],
        [-499990000, +999980000]
      );
    });

    it("Should allow claim of all tokens a user owns in RMRA", async function () {
      const {
        owner,
        investor1,
        remoratoken,
        remoratoken2,
        custodian,
        facilitator,
        allowlist,
        rmra,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryPayoutTests);
      await rmra.approve(saleIntermediary, 1000);

      await allowlist.connect(custodian).allowUser(owner);
      await allowlist.connect(custodian).allowUser(investor1);

      await remoratoken.transfer(investor1.address, 5);
      await remoratoken2.transfer(investor1.address, 5);

      //distribute $1000
      await remoratoken.connect(facilitator).distributePayout(1000);
      await remoratoken2.connect(facilitator).distributePayout(1000);

      const rwaAddrs = [remoratoken.target, remoratoken2.target];
      const payoutStruct = {
        useStablecoin: false,
        useCustomFee: true,
        holder: investor1.address,
        paymentToken: rmra.target,
        feeValue: 0,
        amount: 1000,
        rwaTokens: rwaAddrs,
      };

      await expect(
        await saleIntermediary.connect(facilitator).payoutAll(payoutStruct)
      ).to.changeTokenBalances(rmra, [owner, investor1], [-1000, +1000]);
    });
  });
});
