set +e
s3cmd get s3://diggers/cpan-digger.tar.gz cpan-digger.tar.gz
tar xzf cpan-digger.tar.gz
exit_code=$?
echo $exit_code

./generate.sh

tar czf cpan-digger.tar.gz cpan-digger/
s3cmd put cpan-digger.tar.gz s3://diggers/cpan-digger.tar.gz
