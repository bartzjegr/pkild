package pkild::Model::Certificates;

use strict;
use base 'Catalyst::Model::File';

__PACKAGE__->config(
    root_dir => '/var/tmp/certificate_authority',
);

################################################################################
# Return a list of hashes of lists of hashes that describe the directory tree
################################################################################
sub tree{
    my ($self, $c)=@_;
    my $tree;
    my $node_separator="::";
    my @file_names=$self->list(mode => 'both', recurse =>1);
    my $rootdir=join("/",@{ $self->{'root_dir'}->{'dirs'} });
    $rootdir=~s/^\///;
    @file_names=sort(@file_names);
    my $previous_node='';
    my $type;
    for my $node (@file_names){
        next if $node eq '.';
        # skip directories containing key data
        next if $node=~m/\.ca$/;
        next if $node=~m/private$/;
        next if $node=~m/openssl.cnf$/;
        # We need to know if this is a file, or a directory
        $type="unknown";
        if( -d $node){ $type="folder"; }
        if( -f $node){ $type="file"; }
        $node=~s/$rootdir//g;
        $node=~s/^\///g;
        if(! defined $tree->{$node}){  
            my @nodeparts=split("\/",$node);
            $node=~s/\//$node_separator/g;
            $tree->{$node} = { 
                               'attributes' => { 'id' => $node, 'rel' => $type },
                               'data'       => $nodeparts[$#nodeparts],
                             };
            pop(@nodeparts);
            my $updir=join("$node_separator",@nodeparts);
            if(!defined( $tree->{ $updir }->{'children'} )){
               push( @{ $tree->{ $updir }->{'children'} }, $node );
            }else{
               my $found=0;
               foreach my $child (@{ $tree->{ $updir }->{'children'} }){
                   if($node eq $child){ $found=1;}
               }
               if(! $found){ push( @{ $tree->{ $updir }->{'children'} }, $node ); }
           }
        }
    }
    # now dereference the children to their actual structs.
    foreach my $key (reverse(sort(keys(%{ $tree })))){
        if(defined( $tree->{$key}->{'children'} && $key ne '')){
            for(my $childidx=0; $childidx<=$#{$tree->{$key}->{'children'} }; $childidx++){ 
                if(defined( $tree->{$key}->{'children'}->[$childidx] )){
                    $tree->{$key}->{'children'}->[$childidx] = YAML::Load(YAML::Dump($tree->{ $tree->{$key}->{'children'}->[$childidx] }));
                }else{
                    $tree->{$key}->{'children'}->[$childidx] = undef;
                }
            }
        }
    }
    return $tree->{''}->{'children'};
}

sub sign_certificate{
    use FileHandle;
    use File::Temp qw/ tempfile tempdir /;
    my ($self, $param,$session)=@_;
    my $rootdir="/".join("/",@{ $self->{'root_dir'}->{'dirs'} });
    
    # $param->{'node_name'};
    # $param->{'csr_input'};

    # write out the csr to a temp file
    my $tmpdir = tempdir( 'CLEANUP' => 1 );
    my ($fh, $filename) = tempfile( 'DIR' => $tmpdir );
    print $fh $param->{'csr_input'};
    open(GETCN, "/usr/bin/openssl req -in $filename -noout -text | ");
    while(my $line=<GETCN>){
        print STDERR $line;
    }
#grep "Subject:" | sed -e 's/.*CN=//g' -e 's/\/.*//g'|");
    # get the CN with openssl req -in $temp_file -noout -text | grep "Subject:" | sed -e 's/.*CN=//g' -e 's/\/.*//g'
    # delete the temp file
    # create the $root/$param->{'node_name'};/$cn  directory
    # write out the csr to ${cn}.csr in the node directory
    # sign the csr with "openssl ca -extensions v3_ca -days ${lifetime} -passin fd:0 -out mid-ca.${DOMAIN}.crt -in mid-ca.${DOMAIN}.csr -config root-openssl.cnf -batch
    # write it out as a ${cn}.crt int the node directory
    return "SUCCESS";
}

sub ca_create{
    use FileHandle;
    use Template;
    my ($self, $param,$session)=@_;
    my $rootdir=join("/",@{ $self->{'root_dir'}->{'dirs'} });
    $rootdir=~s/^\///;
    my $template=Template->new();
    my $tpldata;
    if($param->{'ca_domain'}){
        if( ! -d "$rootdir/$param->{'ca_domain'}" ){
            umask(0077);
            mkdir("$rootdir/$param->{'ca_domain'}",0700); 
            mkdir("$rootdir/$param->{'ca_domain'}/private",0700); 
            mkdir("$rootdir/$param->{'ca_domain'}/certs",0700); 
            foreach my $key (keys(%{ $param } )){
                $tpldata->{$key} = $param->{$key};
            }
            foreach my $prefs (@{ $session->{'menudata'}->{'openssl_cnf_prefs'}->{'fields'} }){
                $tpldata->{$prefs->{'name'}} = $prefs->{'value'};
            }
            my $text=$self->openssl_cnf_template(); 
            $tpldata->{'cert_home_dir'}="/$rootdir/$param->{'ca_domain'}";
            $template->process(\$text,$tpldata,"/$rootdir/$param->{'ca_domain'}/openssl.cnf");
            system("/usr/bin/openssl genrsa -out /$rootdir/$param->{'ca_domain'}/private/$param->{'ca_domain'}.key");
            system("/usr/bin/openssl req -new -x509 -nodes -sha1 -days $tpldata->{'ca_default_days'} -key /$rootdir/$param->{'ca_domain'}/private/$param->{'ca_domain'}.key  -out /$rootdir/$param->{'ca_domain'}/$param->{'ca_domain'}.pem -config /$rootdir/$param->{'ca_domain'}/openssl.cnf -batch");
            system("/usr/bin/openssl req -new -sha1 -days $tpldata->{'ca_default_days'} -key /$rootdir/$param->{'ca_domain'}/private/$param->{'ca_domain'}.key  -out /$rootdir/$param->{'ca_domain'}/$param->{'ca_domain'}.csr -config /$rootdir/$param->{'ca_domain'}/openssl.cnf -batch");
            my $fh = FileHandle->new("> /$rootdir/$param->{'ca_domain'}/.ca");
            if (defined $fh) {
               print $fh "";
               $fh->close;
            }
            chmod(0700, "/$rootdir/$param->{'ca_domain'}/.ca");
            return "SUCCESS";
        }
    }
    return "ERROR";
}

sub node_type{
    my ($self, $node)=@_;
    $node =~s/::/\//g;
    my $rootdir="/".join("/",@{ $self->{'root_dir'}->{'dirs'} });
    if(-f "$rootdir/$node"){ return "file"; }
    if(-d "$rootdir/$node"){ 
        if(-f "$rootdir/$node/.ca"){ return "ca"; }
        return "directory"; 
    }
    return undef;
}

sub contents{
    use FileHandle;
    my ($self, $node)=@_;
    $node =~s/::/\//g;
    my $rootdir="/".join("/",@{ $self->{'root_dir'}->{'dirs'} });
    my $contents='';
    if(-f "$rootdir/$node"){ 
        my $fh = FileHandle->new;
        if ($fh->open("< $rootdir/$node")) {
            while(my $line=<$fh>){
                $contents.=$line;
            }
            $fh->close;
            return $contents;
        }
    }
    return undef;
}

sub openssl_cnf_template{
    my ($self)=shift;
    my $the_template = <<_END_TEMPLATE_;
HOME = [\% cert_home_dir \%]
RANDFILE = \$HOME/.rnd
ca-domain = [\% ca_domain \%]
 
[ ca ]
default_ca = CA_default # The default ca section
[ CA_default ]
dir = .
certs = \$dir/certs
crl_dir = \$dir/crl
database = \$dir/index.txt
new_certs_dir = \$dir/newcerts
certificate = \$dir/[\% ca_domain \%].pem
serial = \$dir/serial
crlnumber = \$dir/crlnumber
crl = \$dir/crl.[\% ca_domain \%].pem
private_key = \$dir/private/[\% ca_domain \%].key
RANDFILE = \$dir/private/.rand
x509_extensions = usr_cert
name_opt = ca_default
cert_opt = ca_default
default_days = [\% ca_default_days \%]
default_crl_days= [\% crl_days \%]
default_md = sha1
preserve = no
policy = policy_match
 
[ policy_match ]
countryName = match
stateOrProvinceName = match
organizationName = match
organizationalUnitName = optional
commonName = supplied
emailAddress = optional
 
[ policy_anything ]
countryName = optional
stateOrProvinceName = optional
localityName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
emailAddress = optional
 
[ req ]
default_bits = 1024
default_keyfile = [\% ca_domain \%].pem
distinguished_name = req_distinguished_name
attributes = req_attributes
x509_extensions = v3_ca
 
[ req_distinguished_name ]
countryName = Country Name (2 letter code)
countryName_default = [\% ca_country \%]
countryName_min = 2
countryName_max = 2
stateOrProvinceName = State or Province Name (full name)
stateOrProvinceName_default = [\% ca_state \%]
localityName = Locality Name (eg, city)
localityName_default = [\% ca_localitiy \%]
0.organizationName = Organization Name (eg, company)
0.organizationName_default = [\% ca_org \%]
organizationalUnitName = Organizational Unit Name (eg, section)
organizationalUnitName_default = [\% ca_orgunit \%]
commonName = Common Name (eg, YOUR name)
commonName_max = 64
commonName_default = [\% ca_domain \%]
emailAddress = Email Address
emailAddress_max = 64
emailAddress_default = [\% ca_email \%]
 
[ req_attributes ]
challengePassword = A challenge password
challengePassword_min = 4
challengePassword_max = 20
 
[ usr_cert ]
basicConstraints=CA:FALSE
nsComment = "OpenSSL Generated Certificate"
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
nsCaRevocationUrl = [\% crl_path \%]
 
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
nsCaRevocationUrl = [\% crl_path \%]
 
[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer:always
basicConstraints = CA:true
nsCaRevocationUrl = [\% crl_path \%]
_END_TEMPLATE_

    return $the_template;
}
=head1 NAME

pkild::Model::Certificates - Catalyst File Model

=head1 SYNOPSIS

See L<pkild>

=head1 DESCRIPTION

L<Catalyst::Model::File> Model storing files under
L<>

=head1 AUTHOR

James White

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
