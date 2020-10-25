var fs = require('fs');

fs.writeFileSync(
    'plex_install.sql',
    fs.readFileSync('src/plex_install.sql', 'utf8')
        .replace('@plex.pks', function(){return fs.readFileSync('src/plex.pks', 'utf8')})
        .replace('@plex.pkb', function(){return fs.readFileSync('src/plex.pkb', 'utf8')})
        // Read what this function thing is doing, without it we get wrong results.
        // We have dollar signs in our package body text - the last answer explains:
        // https://stackoverflow.com/questions/9423722/string-replace-weird-behavior-when-using-dollar-sign-as-replacement
);

fs.copyFileSync(
    'src/plex_uninstall.sql', 
    'plex_uninstall.sql'
);