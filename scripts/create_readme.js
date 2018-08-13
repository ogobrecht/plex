// https://medium.freecodecamp.org/introduction-to-npm-scripts-1dbb2ae01633
// https://medium.freecodecamp.org/why-i-left-gulp-and-grunt-for-npm-scripts-3d6853dd22b8
// https://css-tricks.com/why-npm-scripts/

var fs = require('fs');
var packageSpecFile = process.argv[2];
var readmeFile = process.argv[3];
var readmeContent;
var index = 0;
// RegExp Hint: We need to use one big regexp which finds the package itself
// with the comment below or all functions/procedures with the comment above. If
// we separate the regexp into one for the package and one for the
// functions/procedures we would get some overlapping text - the | (or) is
// essential here. If you see many of them and don't understand non capturing
// groups or regexp at all - no problem: put the regexp and the plex package
// spec in the online tool https://regexr.com/ and play around with it.
var regexp = /(\s*create\s*or\s*replace\s*package(?:.|\s)+?is(?:.|\s)+?)\/\*{3,}((?:.|\s)+?)\*{3,}\/|\/\*{3,}((?:.|\s)+?)\*{3,}\/(?:.|\s)+?((?:function|procedure)(?:.|\s)+?;)/ig;
var match;

fs.readFile(packageSpecFile, 'utf8', function (err, text) {
  if (err) throw err;

  while (match = regexp.exec(text)) {
    if (index === 0) {
      // this is the package definition (first match, comment below code)
      readmeContent = match[2] + '\n\nPACKAGE SIGNATURE / META DATA\n\n```sql\n' + match[1] + '```\n\n';
    } else {
      // these are the functions and procedures (all other matches, comment above code)
      readmeContent += match[3] + '\n\nSIGNATURE\n\n```sql\n' + match[4] + '\n```\n\n';
    }
    index++;
  }

  fs.writeFile(readmeFile, readmeContent, function (err) {
    if (err) throw err;
    console.log(readmeFile + ' saved!');
  });

});