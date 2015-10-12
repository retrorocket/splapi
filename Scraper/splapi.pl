#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use WWW::Mechanize;
use Web::Scraper;
#use Data::Dumper;
#use JSON;
use DateTime::Format::Strptime;
use DateTime;
use MongoDB;
use Config::Pit;

#正規表現で開始日時と終了日時のDateTimeオブジェクトを返却する
sub get_datetime(){
    my $element = shift;
    my $str = $element->string_value;
    $str =~ /(.+) ~ (.+)/;
     my $strp = DateTime::Format::Strptime->new(
        pattern   => '%Y/%m/%d %H:%M',
        time_zone => 'Asia/Tokyo',
    );
    my ($year) = (localtime)[5];
    $year = $year + 1900;
    my $start = $year."/".$1;
    my $end = $year."/".$2;
    my $ret = {
        start => $strp->parse_datetime($start),
        end => $strp->parse_datetime($end)
    };
    unless(defined($ret->{start}) && defined($ret->{end})){
        die("Datetime is null.");
    }
    return $ret;
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

# divの内部scraper
my $ins_scraper = scraper {
    process 'span.rule-description', 'rule' => "TEXT";
    process 'span.map-name', 'map_list[]' => "TEXT";
};

#scraper本体
#sub{&開始日時と終了日時をDateオブジェクト化する処理};
my $scraper = scraper {
    process 'span.stage-schedule', 'schedule_list[]' => sub{&get_datetime($_)};
    process 'span.map-name', 'map_list[]' => "TEXT";
    process 'div.stage-list', 'stage_list[]' => $ins_scraper;
    process 'div.festival', 'fes' => "TEXT";
    process 'span.festival-team-info', 'team[]' => sub {
        my $elem = shift;
        my $text = $elem->string_value;
        unless(length($text)){
            return;
        }
        return $text;
    };
};

my $spla = $scraper->scrape( $mech->content );
my $schedule_list = $spla->{schedule_list};

# fes開催中ならfesモードへ
my $fes = $spla->{fes};
if(defined($fes)) {
    printf "fes!";
    my $map_list = $spla->{map_list};
    my $team = $spla->{team};
    my $fes_result = {
        start => $schedule_list->[0]->{start},
        end => $schedule_list->[0]->{end},
        maps => $map_list,
        team => $team
    };
    
    # MongoDB
    my $client = MongoDB::MongoClient->new;
    my $db = $client->get_database( "splapi");
    my $fes_collection = $db->get_collection( "fes" );

    unless($fes_collection->find_one({start => $fes_result->{start}})) {
        $fes_collection->insert($fes_result);
    }
    exit(0);
}
# fesモード終了 -> スクリプト終了
# 以降通常モード
my $stage_list = $spla->{stage_list};

my @regular_list;
my @gachi_list;
my $elem_reg_pos = 0;
my $elem_gachi_pos = 0;

for my $elem (@$stage_list){
    my $rule = $elem->{rule};
    if(defined($rule)){ #ガチ
        my $gachi_content = {
            start => $schedule_list->[ $elem_gachi_pos ]->{start},
            end => $schedule_list->[ $elem_gachi_pos ]->{end},
            maps => $elem->{map_list},
            rule => $rule,
        };
        push(@gachi_list, $gachi_content);
        $elem_gachi_pos++;
    } else { #レギュラー
        my $reg_content = {
            start => $schedule_list->[ $elem_reg_pos ]->{start},
            end => $schedule_list->[ $elem_reg_pos ]->{end},
            maps => $elem->{map_list}
        };
        push(@regular_list, $reg_content);
        $elem_reg_pos++;
    }
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
