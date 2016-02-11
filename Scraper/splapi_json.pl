#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use WWW::Mechanize;
#use Web::Scraper;
#use Data::Dumper;
use JSON;
use Date::Manip;
use DateTime::Format::DateManip;
use MongoDB;
use Config::Pit;

#DateTimeオブジェクトを返却する
sub get_datetime(){
    my $date_str = shift;

    # Date::Manip to DateTime
    my $dm = ParseDate($date_str);
    my $dt = DateTime::Format::DateManip->parse_datetime($dm);
    return $dt;
};

my $mech = WWW::Mechanize->new();
# Config::Pit読み込み
my $config = pit_get( "splapi" );

#ログイン
$mech->get('https://splatoon.nintendo.net/schedule');
$mech->follow_link( url_regex => qr/auth/i );
$mech->submit_form(
    fields => {
        username => $config->{username},
        password => $config->{password}
    }
);

my $res = $mech->get('https://splatoon.nintendo.net/schedule.json');
my $content = $res->content;
my $json = decode_json($content);

#print Dumper $json;

if($json->{festival}){
    print "fes!";
    #fesのjson形式わからないので
    my $retcode = system("perl /home/".$config->{user}."/perl/splapi/splapi.pl");
    exit($retcode);
}

my @regular_list;
my @gachi_list;

for my $elem (@{$json->{schedule}}) {

    my $start_dt = &get_datetime($elem->{datetime_begin});
    my $end_dt = &get_datetime($elem->{datetime_end});

    unless(defined($start_dt) && defined($end_dt)){
        die("Datetime is null.");
    }

    my $stages = $elem->{stages};
    
    my @reg_map;
    for my $reg (@{$stages->{regular}}) {
        #print $reg->{name}."\n";
        push(@reg_map, $reg->{name});
    }
    my $reg_content = {
        start => $start_dt,
        end => $end_dt,
        maps => \@reg_map
    };
    push(@regular_list, $reg_content);
    
    my @gachi_map;
    for my $gachi (@{$stages->{gachi}}) {
        #print $reg->{name}."\n";
        push(@gachi_map, $gachi->{name});
    }
    my $gachi_content = {
        start => $start_dt,
        end => $end_dt,
        maps => \@gachi_map,
        rule => $elem->{gachi_rule}
    };
    push(@gachi_list, $gachi_content);
}

# MongoDB
my $client = MongoDB::MongoClient->new;
my $db = $client->get_database( "splapi" );
my $regular = $db->get_collection( "regular" );
my $gachi = $db->get_collection( "gachi" );

for my $cont (@regular_list){
    if($regular->find_one({start => $cont->{start}})) {
        next;
    }
    $regular->insert($cont);
}
for my $cont2 (@gachi_list){
    if($gachi->find_one({start => $cont2->{start}})) {
        next;
    }
    $gachi->insert($cont2);
}
