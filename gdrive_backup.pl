#!/usr/bin/perl
use strict;
use Net::OAuth2::Profile::WebServer;
use Data::Dumper;
use File::Slurp;
use JSON;
use Getopt::Long;

#Describes the OAuth server to authenticate to
my $server_config_file = "gdrive_backup.conf";
my $source_file;
my $target_doc;
my $file_type;
my $help;

sub usage(){
    print << 'EOF'
gdrive_backup -d <doc name to save to> -s <source file to backup> [-c <configuration file>] [ -f <MIME type> ] [-h]
    Command line tool to upload a document to Google Docs using serialized OAuth token.
    Requires a source file (to upload), and a filename to use on Google Docs. If a doc with this name exists, it will be replaced.
    -f allows you to specify a MIME type for the document. Default is 'text/plain'.
    You have to authorize the app as well, with create_token.pl. 
EOF
}

GetOptions( "config|c=s" => \$server_config_file,
            "source|s=s" => \$source_file,
            "doc|d=s" => \$target_doc,
            "filetype|f=s" => \$file_type,
            "help|h!" => \$help);

usage() and exit unless $source_file and $target_doc and not $help;

my $conf_content;
my $server_config;
my $tok_content;
my $client_token;
my $file_contents;

eval { $conf_content = File::Slurp::read_file($server_config_file) };
die "Failed to open server config file $server_config_file file \r\n $@" if ($@);

eval { $server_config = decode_json($conf_content) };
die "Invalid JSON in server config $server_config_file \r\n $@" if ($@);

#The credentials for OAuth
my $token_file = $server_config->{'token_file'};
eval { $tok_content = File::Slurp::read_file($token_file) };
die "Failed to OAuth credential file $token_file \r\n $@" if ($@);

eval { $client_token = decode_json($tok_content) };
die "Invalid JSON in OAuth credential file $token_file \r\n $@" if ($@);

eval { $file_contents = File::Slurp::read_file($source_file) };
die "Failed to read file to backup - $source_file \r\n $@" if ($@);

my $server = Net::OAuth2::Profile::WebServer->new(
               %{$server_config->{'oauth_conf'}},
               access_type=>'offline',
               );

my $access_token = $server->create_access_token($client_token);

$server->update_access_token($access_token);

my $resp = $access_token->get("https://www.googleapis.com/drive/v2/files?q=title='$target_doc'");

die 'Got HTTP error listing documents'.$resp->code unless $resp->code == 200;

my $id;
my $existing_docs = decode_json($resp->content);

print @{$existing_docs->{'items'}};
if ( @{ $existing_docs->{'items'}} ){
    print $existing_docs->{'items'}->[0]->{'id'};
    $id = $existing_docs->{'items'}->[0]->{'id'};
} else {
    $resp = $access_token->post("https://www.googleapis.com/drive/v2/files/",
                   ['Content-Type'=>'application/json'],
                   encode_json({'title'=> $target_doc}));
    die "Failed to create file, HTTP error ".$resp->code unless $resp->code == 200;
    $existing_docs = decode_json($resp->content);
    $id = $existing_docs->{'id'};
}

$resp = $access_token->put(
          "https://www.googleapis.com/upload/drive/v2/files/$id?uploadType=media&convert=true",
          ['Content-Type'=>$file_type],
          $file_contents);

die "Failed to upload, HTTP error ".$resp->code unless $resp->code == 200;

