// https://medium.freecodecamp.org/introduction-to-npm-scripts-1dbb2ae01633
// https://medium.freecodecamp.org/why-i-left-gulp-and-grunt-for-npm-scripts-3d6853dd22b8
// https://css-tricks.com/why-npm-scripts/

var plpks2mddoc = require('./lib/plpks2mddoc');
var inputFiles = process.argv[2];     // first command line parameter
var outputTemplate = process.argv[3]; // second command line parameter
plpks2mddoc(inputFiles, outputTemplate);