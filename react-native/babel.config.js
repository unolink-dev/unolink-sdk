// Only for the tests (jest); apps compile src/ with their own Metro/Babel setup.
module.exports = {
  presets: [["@babel/preset-env", { targets: { node: "current" } }], "@babel/preset-typescript"],
}
