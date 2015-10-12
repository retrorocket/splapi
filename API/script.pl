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

# レスポンスとして返却するJSONのマップ
sub create_result_map(){
    my $mode = shift;
    my $entry = shift;
    my $start = $entry->{start}->set_time_zone($TZ);
    my $end = $entry->{end}->set_time_zone($TZ);
    my $result_map = {start=>$start->datetime, end=>$end->datetime, maps=>$entry->{maps}};
    if($mode eq $GACHI) {
        $result_map->{rule} = $entry->{rule};
    }
    if($mode eq $FES) {
        $result_map->{team} = $entry->{team};
    }
    return $result_map;
}

# mongoに送るクエリのマップ
sub create_query_map(){
    my $mode = shift;
    my $query = shift;
    my $query_map = {};
    if ($query->{rule} && $mode eq $GACHI) {
        $query_map->{rule} = $query->{rule};
    }
    if ($query->{map}) {
        # mongoはmapsで登録してあるが、検索クエリは単数で探すのでmap
        $query_map->{maps} = $query->{map};
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
    my $result_map = &create_result_map($mode, $entry);
    push(@result, $result_map);
    return \@result;
}

# 返却値が複数なもの
sub all_get(){
    my $mode = shift;
    my $query = shift;
    my $position = shift;
    
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
        my $result_map = &create_result_map($mode, $entry);
        push(@result, $result_map);
    }
    return \@result;
}

get '/' => sub {
    my $self = shift;
    return $self->render(template => 'index', format => 'html');
} => 'index';

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
    my $query = $self->req->params->to_hash;
    my $result;
    if($time eq "now" || $time eq "next" || $time eq "prev" ){
        $result = &one_get($mode, $query, $time);
    } elsif($time eq "next_all" || $time eq "prev_all") {
        $result = &all_get($mode, $query, $time);
    } else {
        return $self->render(json =>{'error' => $ERROR_404}, status => '404');
    }
    if ($result == -1){
        return $self->render(json =>{'error' => $ERROR_404}, status => '404');
    }
    return $self->render(json =>{'result' => $result});
} => 'time';

app->start;
