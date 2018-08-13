'use strict';
var fs = require('fs');
var glob = require('glob');
var createSingleDoc = function (pathToSpec, pathToDoc) {
  var directory, file, content, match;

  // We need to use one big regexpSpec which finds the package itself with the comment below or all functions/procedures with the comment above. If we separate the regexpSpec into one for the package and one for the functions/procedures we would get some overlapping text - the | (or) is essential here. If you see many of them and don't understand non capturing groups or regexpSpec at all - no problem: put the regexpSpec and the plex package spec in the online tool https://regexr.com/ and play around with it.
  var regexpSpec = /(\s*create\s*or\s*replace\s*package(?:.|\s)+?is(?:.|\s)+?)\/\*{3,}((?:.|\s)+?)\*{3,}\/|\/\*{3,}((?:.|\s)+?)\*{3,}\/(?:.|\s)+?((?:function|procedure)(?:.|\s)+?;)/ig;
  
  // This regex is taken from https://regexr.com/3dns9 and splits a URL it its components: $1 - folder path. $2 - file name(including extension). $3 - file name without extension. $4 - extension. $5 - extension without dot sign. $6 - variables.
  var regexpPath = /(.*(?:\\|\/)+)?((.*)(\.([^?\s]*)))\??(.*)?/i;

  // set default
  if (!pathToDoc) pathToDoc = '{directory}{file}';
  pathToDoc = pathToDoc.replace(/\.\w*$/, '');

  // extract directory and file from pathToSpec for replacements of {directory} and {file} in pathToDoc
  match = pathToSpec.match(regexpPath);
  directory = match[1] || '';
  file = match[3];

  // do the final replacements
  pathToDoc = pathToDoc.replace('{directory}', directory).replace('{file}', file) + '.md';

  fs.readFile(pathToSpec, 'utf8', function (err, text) {
    var counter = 0;
    if (err) throw err;
    if (!regexpSpec.test(text)) {
      console.log(pathToSpec + ' contains no code to process - are you sure this is a PL/SQL package?');
    } else {
      // reset regexp index to find all occurrences with exec - see also: https://www.tutorialspoint.com/javascript/regexp_lastindex.htm
      regexpSpec.lastIndex = 0;
      while (match = regexpSpec.exec(text)) {
        if (counter === 0) {
          // this is the package definition (first match, comment below code)
          content = match[2] + '\n\nSIGNATURE\n\n```sql\n' + match[1] + '```\n\n';
        } else {
          // these are the functions and procedures (all other matches, comment above code)
          content += match[3] + '\n\nSIGNATURE\n\n```sql\n' + match[4] + '\n```\n\n';
        }
        counter++;
      }
      fs.writeFile(pathToDoc, content, function (err) {
        if (err) throw err;
        console.log(pathToSpec + ' => ' + pathToDoc);
      });
    }
  });

};

var plpks2mddoc = function (inputFiles, outputTemplate) {
  var options = {
    matchBase: false
  };
  if (!inputFiles) inputFiles = '*.pks';
  if (!outputTemplate) outputTemplate = '{directory}{file}.md';
  glob(inputFiles, options, function (err, files) {
    if (err) throw err;
    files.forEach(function (path) {
      createSingleDoc(path, outputTemplate);
    });
  })
};

module.exports = plpks2mddoc;