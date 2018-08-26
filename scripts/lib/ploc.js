'use strict';
var fs = require('fs');
var glob = require('glob');
var ploc = {};
ploc.util = {};

ploc.util.reverseString = function (string) {
  return string.split("").reverse().join("");
};

ploc.util.capitalizeString = function (string) {
  return string.charAt(0).toUpperCase() + string.substring(1).toLowerCase();
};

ploc.util.getMarkdownHeader = function (level, header, anchor) {
  var markdownHeader;
  // create HTML or Markdown header depending on anchor length
  if (anchor.length > 0) {
    markdownHeader = '<h' + level + '>' +
      '<a id="' + anchor + '"></a>' +
      header +
      '</h' + level + '>';
    markdownHeader += '\n<!--' + (level === 1 ? '=' : '-').repeat((markdownHeader.length - 7)) + '-->';
  } else {
    markdownHeader = header + '\n' + (level === 1 ? '=' : '-').repeat(header.length);
  }
  return markdownHeader;
};

ploc.util.getAnchor = function (name) {
  return name.trim().toLowerCase().replace(/[^\w\- ]+/g, '').replace(/\s/g, '-').replace(/\-+$/, '');
};


ploc.util.getOutFilePath = function (inFilePath, outFilePattern) {
  if (!outFilePattern) outFilePattern = '{folder}/{file}.md';
  var folder, file, match;
  // This regex is taken from https://regexr.com/3dns9 and splits a URL it its components: $1 - folder path. $2 - file name(including extension). $3 - file name without extension. $4 - extension. $5 - extension without dot sign. $6 - variables.
  var regexp = /(.*(?:\\|\/)+)?((.*)(\.([^?\s]*)))\??(.*)?/i;

  // extract folder and file from inFilePath for replacements of {folder} and {file} in outFilePattern
  match = inFilePath.match(regexp);
  folder = (match[1] ? match[1].replace(/\/$/, '') : '');
  file = match[3];

  // do the final replacements and return
  return outFilePattern.replace('{folder}', folder).replace('{file}', file);
}


ploc.util.getDocData = function (inFilePath) {
  // we need to work on a reversed string, so the keywords for package, function and so on are looking ugly...
  var regexp = /\/\*{2,}\s*((?:.|\s)+?)\s*\*{2,}\/\s*((?:.|\s)*?\s*([\w$#]+|".+?")(?:\.(?:[\w$#]+|".+?"))?\s+(reggirt|epyt|erudecorp|noitcnuf|egakcap))\s*/ig;
  var match;
  var code = ploc.util.reverseString(fs.readFileSync(inFilePath, 'utf8'));
  var usedAnchors = [];
  var data = {};
  data.toc = '';
  data.items = [];

  // get base attributes
  if (!regexp.test(code)) {
    console.warn(inFilePath + ' contains no code to process!');
  } else {
    // reset regexp index to find all occurrences with exec - see also: https://www.tutorialspoint.com/javascript/regexp_lastindex.htm
    regexp.lastIndex = 0;
    while (match = regexp.exec(code)) {
      var item = {};
      item.description = ploc.util.reverseString(match[1]);
      item.signature = ploc.util.reverseString(match[2]);
      item.name = ploc.util.reverseString(match[3]);
      item.type = ploc.util.capitalizeString(ploc.util.reverseString(match[4]));
      data.items.push(item);
    }
  }

  // calculate header and anchor
  data.items.reverse().forEach(function (item, i) {
    data.items[i].header = data.items[i].type + ' ' + data.items[i].name;
    data.items[i].anchor = ploc.util.getAnchor(item.name);

    // create GitHub compatible toc
    if (usedAnchors.indexOf(data.items[i].anchor) !== -1) {
      var j = 1;
      while (usedAnchors.indexOf(data.items[i].anchor + '-' + j) !== -1 && j++ <= 10);
      data.items[i].anchor = data.items[i].anchor + '-' + j;
    }
    usedAnchors.push(data.items[i].anchor);
    data.toc += '- [' + data.items[i].header + '](#' + data.items[i].anchor + ')\n';
  });

  return data;
};


ploc.util.file2doc = function (inFilePath, minItemsForToc) {
  if (!minItemsForToc) minItemsForToc = 3;
  var doc = '';
  var docData = ploc.util.getDocData(inFilePath);
  var provideToc = (docData.items.length >= minItemsForToc);
  if (provideToc) doc += '\n' + docData.toc + '\n\n';

  docData.items.forEach(function (item, i) {
    var level = (i === 0 ? 1 : 2);
    var header = item.header;
    var anchor = (provideToc ? item.anchor : '');
    doc += ploc.util.getMarkdownHeader(level, header, anchor) + '\n\n' +
      item.description + '\n\n' +
      'SIGNATURE\n\n' +
      '```sql\n' +
      item.signature + '\n' +
      '```\n\n\n';
  });
  return doc;
};


ploc.files2doc = function (inFilePattern, outFilePattern, minItemsForToc) {
  var outFilePath;
  var options = {
    matchBase: false
  };
  if (!inFilePattern) inFilePattern = '*.pks';
  if (!outFilePattern) outFilePattern = '{folder}{file}.md';
  glob(inFilePattern, options, function (err, files) {
    if (err) throw err;
    files.forEach(function (inFilePath) {
      outFilePath = ploc.util.getOutFilePath(inFilePath, outFilePattern);
      console.log(inFilePath + ' => ' + outFilePath);
      fs.writeFileSync(
        outFilePath,
        ploc.util.file2doc(inFilePath, minItemsForToc)
      );
    });
  })
};


module.exports = ploc;