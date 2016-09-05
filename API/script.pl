#!/usr/bin/perl

use strict;
use warnings;
use utf8;

#use Data::Dumper;
use MongoDB;
use Mojolicious::Lite;
use DateTime::Format::DateParse;

app->config(
    hypnotoad => {
        listen => ['http://*:8092'],
    },
);

app->renderer->default_format('json');

app->hook('before_dispatch' => sub {
    my $self = shift;
    if ($self->req->headers->header('X-Forwarded-Host')) {
        #Proxy Path setting
        my $path = shift @{$self->req->url->path->parts};
        push @{$self->req->url->base->path->parts}, $path;
    }
    $self->res->headers->header('Access-Control-Allow-Origin' => '*');
});

### 定数とか ###
#for debug
#my $log = app->log;

# CONST (general)
my $TZ = "Asia/Tokyo";
my $GACHI = "gachi";
my $REGULAR = "regular";
my $FES = "fes";
my $DBNAME = "splapi";
# CONST (error)
my $ERROR_404 = "Not found.";

# collection map
my $collection_map = {gachi => $GACHI, regular => $REGULAR, fes => $FES};

# stat.ink stage map
my $stat_ink_map = {
    "アンチョビットゲームズ" => "anchovy",
    "アロワナモール" => "arowana",
    "Ｂバスパーク" => "bbass",
    "デカライン高架下" => "dekaline",
    "ハコフグ倉庫" => "hakofugu",
    "ヒラメが丘団地" => "hirame",
    "ホッケふ頭" => "hokke",
    "キンメダイ美術館" => "kinmedai",
    "マヒマヒリゾート＆スパ" => "mahimahi",
    "マサバ海峡大橋" => "masaba",
    "モンガラキャンプ場" => "mongara",
    "モズク農園" => "mozuku",
    "ネギトロ炭鉱" => "negitoro",
    "シオノメ油田" => "shionome",
    "ショッツル鉱山" => "shottsuru",
    "タチウオパーキング" => "tachiuo"
};

# stat.ink rule map
my $stat_ink_rule_map = {
    "ガチエリア" => "area",
    "ガチヤグラ" => "yagura",
    "ガチホコ" => "hoko"
};

### サブルーチン ###
# レスポンスとして返却するJSONのマップ
sub create_result_map(){
    my $mode = shift;
    my $entry = shift;
    my $stat_ink_mode = shift;
    
    my $start = $entry->{start}->set_time_zone($TZ);
    my $end = $entry->{end}->set_time_zone($TZ);
    my $result_map = {start=>$start->datetime, end=>$end->datetime, maps=>$entry->{maps}};
    if($stat_ink_mode){
        my $origin_maps = $entry->{maps};
        $result_map->{maps} = &convert_stat_ink_map($origin_maps);
    }
    if($mode eq $GACHI) {
        $result_map->{rule} = $entry->{rule};
        if($stat_ink_mode){
            my $origin_rule = $entry->{rule};
            $result_map->{rule} = &convert_stat_ink_rule($origin_rule);
        }
    }
    if($mode eq $FES) {
        $result_map->{team} = $entry->{team};
    }
    return $result_map;
}

# stat.ink用のstage mapに変換する
sub convert_stat_ink_map(){
    my $origin_maps = shift;
    my @results;
    for my $elem (@$origin_maps){
        my $stat_elem = $stat_ink_map->{$elem};
        unless($stat_elem){
            die("unknown map"); #即死
        }
        my $result = {origin_name => $elem, stat_ink_name => $stat_elem};
        push(@results, $result);
    }
    return \@results;
}
# stat.ink用のrule mapに変換する
sub convert_stat_ink_rule(){
    my $origin_rule = shift;
    my $stat_elem = $stat_ink_rule_map->{$origin_rule};
    unless($stat_elem){
        die("unknown rule"); #即死
    }
    my $result = {origin_name => $origin_rule, stat_ink_name => $stat_elem};
    return $result;
}

# in句を使用する
sub create_ormap(){
    my $query = shift;
    my @list = split(/,/,$query,5);
    my %hash;
    my @elements = grep { ! $hash{ $_ }++ } @list;
    my $length = @elements;
    if($length < 2) {
        return $query;
    }
    return { '$in' => \@elements };
}


# mongoに送るクエリのマップ
sub create_query_map(){
    my $mode = shift;
    my $query = shift;
    my $query_map = {};
    if ($query->{rule} && $mode eq $GACHI) {
        $query_map->{rule} = &create_ormap($query->{rule});
    }
    if ($query->{map}) {
        # mongoはmapsで登録してあるが、検索クエリは単数で探すのでmap
        $query_map->{maps} = &create_ormap($query->{map});
    }
    if($query->{team} && $mode eq $FES) {
        $query_map->{team} = $query->{team};
    }
    return $query_map;
}

# 返却値が絶対に1つにしかならないもの
sub one_get(){
    my $mode = shift;
    my $query = shift;
    my $position = shift;
    my $stat_ink_mode = shift;

    my $collection_name  = $collection_map->{$mode};
    unless($collection_name) {
        return -1;
    }

    # クエリ生成
    my $current_date = DateTime::Format::DateParse->parse_datetime($query->{date}, $TZ ) || DateTime->now;
    my $query_map = &create_query_map($mode, $query);
    if ($position eq "next") {
        $query_map->{start} = {'$gt' => $current_date};
        $query_map->{end} = {'$gt' => $current_date};
    }
    if ($position eq "now") {
        $query_map->{start} = {'$lte' => $current_date};
        $query_map->{end} = {'$gt' => $current_date};
    }
    if ($position eq "prev") {
        $query_map->{start} = {'$lt' => $current_date};
        $query_map->{end} = {'$lt' => $current_date};
    }
    
    # MongoDB
    my $client = MongoDB::MongoClient->new;
    my $db = $client->get_database( $DBNAME );
    my $collection = $db->get_collection( $collection_name );
    my $entry;
    if($position eq "prev") {
        my $temp = $collection->find($query_map)->sort( { end => -1 } )->limit(1);
        $entry = $temp->next;
    } else {
        $entry = $collection->find_one($query_map);
    }
    my @result;
    unless($entry){
        return \@result;
    }
    my $result_map = &create_result_map($mode, $entry, $stat_ink_mode);
    push(@result, $result_map);
    return \@result;
}

# 返却値が複数なもの
sub all_get(){
    my $mode = shift;
    my $query = shift;
    my $position = shift;
    my $stat_ink_mode = shift;
    
    my $collection_name = $collection_map->{$mode};
    unless($collection_name) {
        return -1;
    }

    #クエリ生成
    my $current_date = DateTime::Format::DateParse->parse_datetime($query->{date}, $TZ ) || DateTime->now;
    my $to_date = DateTime::Format::DateParse->parse_datetime($query->{to}, $TZ ) || "";
    my $query_map = &create_query_map($mode, $query);
    if($position eq "next_all") {
        $query_map->{start} = {'$gt' => $current_date};
        if($to_date) {
            $query_map->{end} = {'$lte' => $to_date};
        }
    }
    if($position eq "now") {
        if($query->{date}) {
            $query_map->{start} = {'$gte' => $current_date};
        }
        if($to_date) {
            $query_map->{end} = {'$lte' => $to_date};
        }
    }
    if($position eq "prev_all") {
        $query_map->{end} = {'$lt' => $current_date};
        if($to_date) {
            $query_map->{start} = {'$gte' => $to_date};
        }
    }
    # MongoDB
    my $client = MongoDB::MongoClient->new;
    my $db = $client->get_database( $DBNAME );
    my $collection = $db->get_collection( $collection_name );
    my $all = $collection->find($query_map);
    my @result;
    while ( my $entry = $all->next ) {
        my $result_map = &create_result_map($mode, $entry, $stat_ink_mode);
        push(@result, $result_map);
    }
    return \@result;
}

# 返却値が配列のもの
sub array_get(){
    my $mode = shift;
    # MongoDB
    my $client = MongoDB::MongoClient->new;
    my $db = $client->get_database( $DBNAME );
    my $collection = $db->get_collection( $mode );
    my $all = $collection->find_one();
    return $all->{$mode};
}

### Routing ###
#formats無効化
under [format => 0];

get '/' => sub {
    my $self = shift;
    return $self->render(template => 'index', format => 'html');
} => 'index';

get '/gachi/rules' => sub {
    my $self = shift;
    my $mode = "rules";
    my $result = &array_get($mode);
    return $self->render(json =>{$mode => $result});
} => 'rules';

get '/maps' => sub {
    my $self = shift;
    my $mode = "maps";
    my $result = &array_get($mode);
    return $self->render(json =>{$mode => $result});
} => 'maps';

get '/weapons' => sub {
    my $self = shift;
    my $mode = "weapons";
    my $result = &array_get($mode);
    return $self->render(json =>{$mode => $result});
} => 'weapons';

get '/:mode' => sub {
    my $self = shift;
    my $mode = $self->param('mode');
    my $query = $self->req->params->to_hash;
    my $result = &all_get($mode, $query, "now");
    if ($result == -1){
        return $self->render(json =>{'error' => $ERROR_404}, status => '404');
    }
    return $self->render(json =>{'result' => $result});
} => 'all';

get '/:mode/:time' => sub {
    my $self = shift;
    my $mode = $self->param('mode');
    my $time = $self->param('time');
    my $stat_ink_mode = 0;
    if($self->param('stat_ink') eq "on"){
        $stat_ink_mode = 1;
    }
    my $query = $self->req->params->to_hash;
    my $result;
    if($time eq "now" || $time eq "next" || $time eq "prev" ){
        $result = &one_get($mode, $query, $time, $stat_ink_mode);
    } elsif($time eq "next_all" || $time eq "prev_all") {
        $result = &all_get($mode, $query, $time, $stat_ink_mode);
    } else {
        return $self->render(json =>{'error' => $ERROR_404}, status => '404');
    }
    if ($result == -1){
        return $self->render(json =>{'error' => $ERROR_404}, status => '404');
    }
    return $self->render(json =>{'result' => $result});
} => 'time';

app->start;
