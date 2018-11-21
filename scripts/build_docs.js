var ploc = require('ploc');
var inFilePattern  = process.argv[2]; // first command line parameter
var outFilePattern = process.argv[3]; // second one
var minItemsForToc = process.argv[4]; // third one

ploc.files2docs(inFilePattern, outFilePattern, minItemsForToc)
