#!/usr/bin/perl
use Data::Dumper;
use WWW::Mechanize;
use File::Temp qw/ tempfile tempdir /;
use Sys::Hostname::Long;
$host_long = hostname_long;

sub dotheneedful{
    my $cnstr=shift if @_;
    my $uri="https://loki.websages.com";
    my $mech = WWW::Mechanize->new();
    my $successful_create=0;
    my $successful_revoke=0;
    my $successful_create_after_revoke=0;
    my $count=0;
        while( ($successful_create_after_revoke==0)  && ($count < 10) ){
        $mech->get( $uri );
        # find the legends on the page to determine which form we're seeing
        my @legends = grep(/<legend>.*<\/legend>/, split('\n',$mech->content)); 
        if($#legends<0){
            print "No legends found.\n";
            return -1;
        }
        for(my $idx=0; $idx<=$#legends; $idx++){
            $legends[$idx]=~s/.*<legend>//;
            $legends[$idx]=~s/<\/legend>.*//;
        }
        # if there is a certificate, then we want to revoke it (or why are we running?)
        if(grep /Valid Certificate Found/, @legends){
            unless($successful_create_after_revoke == 1){
                print "valid cert found. Revoking\n";
                $mech->click_button( 'name' => 'revoke' );
                $successful_revoke=1;
            }
        # if there not a certificate, then we want to create one.
        }elsif(grep /Certificate Signing Request/, @legends){
            print "no cert found. creating a certificate signing request and posting for signature\n";
            # make our tmp dir
            my  $dir = tempdir( CLEANUP => 1 );
            # make our key
            system("cd $dir; /usr/bin/openssl genrsa -out $host_long.key 2048");
            # get our openssl.cnf
            $mech->follow_link( 'text' => 'OpenSSL config for batch CSR creation' );
            open(OPENSSLCNF,">$dir/openssl.cnf");
            print OPENSSLCNF $mech->content."\n";
            close(OPENSSLCNF);
            $mech->back();
            # create our CSR 
            system("cd $dir; /usr/bin/openssl req -new -sha1 -days 90 -key $host_long.key -out $host_long.csr -config openssl.cnf -batch");
            # post our CSR
            my $csr='';
            print "Submitting our CSR\n";
            open(CSR,"$dir/$host_long.csr");
            while(my $line=<CSR>){
                $csr.=$line; 
            }
            close(CSR);
            $mech->submit_form( with_fields => { 'csr_request'    => $csr });
            # Retrieve our cert
            print "Retrieving our certificate -> $host_long.pem\n";
            $mech->get("$uri/?get=certificate");
            ########################################################################
            # install our cert and key                                             #
            #                                                                      #
            open(CERTFILE, ">/tmp/$host_long.pem");
            print CERTFILE $mech->content;
            close(CERTFILE);
            system("/bin/mv $dir/$host_long.key /tmp/$host_long.key");
            #print $mech->content;
            #                                                                      #
            ########################################################################
            # validate our cert...
            $successful_create=1;
            if($successful_revoke==1){
                $successful_create_after_revoke=1;
            }
            $mech->back();
        }elsif(grep /No certificate tree found/, @legends){
            print "We need to create the tree.\n";
            foreach my $form ($mech->forms()){
                if($form->inputs() < 1){
                    print "We do not have administrator rights. Can not create the tree.\n";
                    dotheneedful({ 'username' => 'whitejs', 'password' => $ENV{'WHITEJS_PASSWD'} });
                }else{
                    print "We have administrator rights. Creating the tree\n";
                    $mech->click( 'create_cert_tree' );
                }
            }
        }elsif(grep /Please [Ll]og [Ii]n/, @legends){
            print "We need to Authenticate.\n";
            $mech->submit_form(
                                with_fields => {
                                                 'username'    => $cnstr->{'username'},
                                                 'password'    => $cnstr->{'password'},
                                               }
                              );
        }else{
            print "Unhandled legends found:\n";
            print join("\n",@legends)."\n";
        }
        $count++;
    }
}

dotheneedful({ 'username' => 'loki', 'password' => $ENV{'LOKI_PASSWD'} });
