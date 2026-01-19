export default () => ({
  port: parseInt(process.env.PORT || '3000', 10),
  sui: {
    network: process.env.SUI_NETWORK || 'testnet',
    packageId: process.env.PACKAGE_ID || '0x0',
  },
});
