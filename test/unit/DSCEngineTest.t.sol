// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, , weth, , ) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /////////////////////////
    /// Constructor Tests ///
    /////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() external {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////
    /// Price Tests ///
    ///////////////////

    function testGetUsdValue() external {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() external {
        uint256 usdAmount = 100e18;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    ///////////////////////////////
    /// depositCollateral Tests ///
    ///////////////////////////////

    function testRevertsIfCollateralZero() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() external {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        external
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCanDepositCollateralWithoutMinting()
        external
        depositedCollateral
    {
        uint256 dscMintedByUser = dsc.balanceOf(USER);
        assertEq(dscMintedByUser, 0);
    }

    /////////////////////
    /// mintDsc Tests ///
    /////////////////////

    function testCanMintAndUpdateBalance() external depositedCollateral {
        vm.startPrank(USER);
        engine.mintDsc(100);
        vm.stopPrank();
        assertEq(dsc.balanceOf(USER), 100);
    }

    function testMintDscRevertsIfHealthFactorIsBroken()
        external
        depositedCollateral
    {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                1e17
            )
        );
        engine.mintDsc(1e5);
        vm.stopPrank();
    }

    /////////////////////
    /// burnDsc Tests ///
    /////////////////////

    function testBurnDscRevertsIfNoCollateralIsDeposited() external {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughDSCBalance.selector);
        engine.burnDsc(1);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfDscBalanceIsInsufficient()
        external
        depositedCollateral
    {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughDSCBalance.selector);
        engine.burnDsc(1e5);
        vm.stopPrank();
    }

    function testCanBurnDsc() external depositedCollateral {
        vm.startPrank(USER);
        engine.mintDsc(1000);
        dsc.approve(address(engine), 1000);
        engine.burnDsc(10);
        vm.stopPrank();
        assertEq(dsc.balanceOf(USER), 990);
    }

    ////////////////////////////
    /// depositAndMint Tests ///
    ////////////////////////////

    
}
