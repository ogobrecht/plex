// https://medium.freecodecamp.org/introduction-to-npm-scripts-1dbb2ae01633
// https://medium.freecodecamp.org/why-i-left-gulp-and-grunt-for-npm-scripts-3d6853dd22b8
// https://css-tricks.com/why-npm-scripts/

var ploc = require('./lib/ploc')
var inFilePattern = process.argv[2] // first command line parameter
var outFilePattern = process.argv[3] // second command line parameter
var minItemsForToc = process.argv[4] // third command line parameter
ploc.files2doc(inFilePattern, outFilePattern, minItemsForToc)
