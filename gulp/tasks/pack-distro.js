var gulp = require('gulp');
var shell = require('shelljs');

var cwd = process.cwd();
var repo = 'https://github.com/revagomes/pece-distro.git';

gulp.task('pack-distro', function () {
  shell.exec('git clone ' + repo + ' distro');
});
