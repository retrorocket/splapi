#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use LWP::UserAgent;
use HTTP::Request::Common;
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

# Config::Pit読み込み
my $config = pit_get( "splapi" );

# JSON取得
## LWP::UserAgent設定
my $ua = LWP::UserAgent->new;
$ua->cookie_jar({file =>"cookie.txt", autosave=>1 });
$ua->agent("splapi schedule getter (http://splapi.retrorocket.biz)");

## 認証用URL取得
my $req = POST( "https://splatoon.nintendo.net/users/auth/nintendo");
my $res_location = $ua->request($req);
my $location = $res_location->header('location');

## 認証用パラメータ設定
my $dummy_url = URI->new();
$dummy_url->query_form(
    'nintendo_authenticate' => '',
    'nintendo_authorize' => '',
    'scope' => '',
    'lang' => 'ja-JP' ,
    'username' => $config->{username},
    'password' => $config->{password}
);

## 認証用URLアクセス
my $url = URI->new($location.$dummy_url->query);
my $req_auth = POST( $url );
my $res_auth = $ua->request($req_auth);

## JSON取得
my $location_auth = $res_auth->header('location');
my $res_callback = $ua->get($location_auth);

my $res = $ua->get('https://splatoon.nintendo.net/schedule.json?utf8=%E2%9C%93&locale=ja');

my $content = $res->content;
my $json = decode_json($content);

#print Dumper $json;

## fes開催
if($json->{festival}){
    print "fes!";
    my $fes_result;
    for my $elem (@{$json->{schedule}}) {
        my $start_dt = &get_datetime($elem->{datetime_begin});
        my $end_dt = &get_datetime($elem->{datetime_end});

        unless(defined($start_dt) && defined($end_dt)){
            die("Datetime is null.");
        }

        my @fes_stages;
        for my $fes_stage (@{$elem->{stages}}){
            push(@fes_stages, $fes_stage->{name});
        }
        
        my @team;
        push(@team, $elem->{team_alpha_name});
        push(@team, $elem->{team_bravo_name});
        
        $fes_result = {
            start => $start_dt,
            end => $end_dt,
            maps => \@fes_stages,
            team => \@team
        };
    }
    
    # MongoDB
    my $client = MongoDB::MongoClient->new;
    my $db = $client->get_database( "splapi");
    my $fes_collection = $db->get_collection( "fes" );

    unless($fes_collection->find_one({start => $fes_result->{start}})) {
        $fes_collection->insert($fes_result);
    }
    exit(0);
}

## 通常
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
