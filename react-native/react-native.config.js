// Autolinking: the Android package class (iOS is found through the podspec).
module.exports = {
  dependency: {
    platforms: {
      android: {
        packageImportPath: "import dev.unolink.reactnative.RNUnolinkPackage;",
        packageInstance: "new RNUnolinkPackage()",
      },
    },
  },
}
