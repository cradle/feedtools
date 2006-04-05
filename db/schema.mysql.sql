-- Example MySQL schema
  CREATE TABLE `cached_feeds` (
    `id`              int(10) unsigned NOT NULL auto_increment,
    `href`            varchar(255) default NULL,
    `title`           varchar(255) default NULL,
    `link`            varchar(255) default NULL,
    `feed_data`       longtext default NULL,
    `feed_data_type`  varchar(20) default NULL,
    `http_headers`    text default NULL,
    `last_retrieved`  datetime default NULL,
    PRIMARY KEY  (`id`)
  )
