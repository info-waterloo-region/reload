set search_path to tempdb;

-- tblOrgName.Level integer null COMPUTE ((length(sort_key)-1)/5)
drop function if exists name_level_compute() cascade;
create function name_level_compute()
  returns trigger
  as $$
    begin
      update tblorgname
      set level = ((length(sort_key)-1)/5)
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists name_level_compute on tblorgname;
create trigger name_level_compute
  after insert or update of sort_key
  on tblorgname
  for each row
  execute procedure name_level_compute();

-- call org_modified() when related tables change: tblcomm, org_comm_rel, etc
drop type if exists org_modified cascade;
create type org_modified as (org_id integer, modified timestamp);

-- dropping org_modified type cascades to org_modified() function
drop function if exists org_modified(org_id integer);
create function org_modified(org_id integer)
  returns org_modified
  as $$
    update org
    set modified = now()
    where id = $1
    returning id, modified;
  $$ language sql;

-- skipping WebChangeTemplate
-- skipping WebAddTemplate
-- skipping WebDataChange
-- skipping DeleteIndex
-- skipping meta_insert_orgname
-- skipping InsertIndex
-- skipping org_meta_delete_names
-- skipping meta_insert_service
-- skipping meta_delete_orgname
-- skipping meta_update_orgname
-- skipping meta_update_service

-- activeDate (org.isactive)
drop function if exists active_or_deleted() cascade;
create function active_or_deleted()
  returns trigger
  as $$
    begin
      update org
      set deleted = (case isactive when true then null else now() end)
      where org.id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists is_active on org;
create trigger is_active
  after update of isactive
  on org
  for each row
  execute procedure active_or_deleted();

-- skipping meta_delete_service
-- skipping meta_update_cicid
-- skipping org_meta_insert_names
-- skipping org_meta_insert_thes
-- skipping org_meta_delete_thes

-- track deletions with org_rel_del table
-- org_address_del (org_address_rel)
drop function if exists address_deleted() cascade;
create function address_deleted()
  returns trigger
  as $$
    begin
      insert into org_rel_del(org_id,rel_id,added,note,deleted,table_id)
      values(OLD.org_id, OLD.address_id, OLD.added, OLD.note, now(), 271);
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists address_deleted on org_address_rel;
create trigger address_deleted
  after delete
  on org_address_rel
  for each row
  execute procedure address_deleted();

-- org_comm_del (org_comm_rel)
drop function if exists comm_deleted() cascade;
create function comm_deleted()
  returns trigger
  as $$
    begin
      insert into org_rel_del(org_id,rel_id,added,note,deleted,table_id)
      values(OLD.org_id, OLD.comm_id, OLD.added, OLD.note, now(), 270);
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists comm_deleted on org_comm_rel;
create trigger comm_deleted
  after delete
  on org_comm_rel
  for each row
  execute procedure comm_deleted();

-- org_contact_del (org_contact_rel)
drop function if exists contact_deleted() cascade;
create function contact_deleted()
  returns trigger
  as $$
    begin
      insert into org_rel_del(org_id,rel_id,added,note,deleted,table_id)
      values(OLD.org_id, OLD.contact_id, OLD.added, OLD.note, now(), 272);
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists contact_deleted on org_contact_rel;
create trigger contact_deleted
  after delete
  on org_contact_rel
  for each row
  execute procedure contact_deleted();

-- org_service_del (org_service_rel)
drop function if exists service_deleted() cascade;
create function service_deleted()
  returns trigger
  as $$
    begin
      insert into org_rel_del(org_id,rel_id,added,note,deleted,table_id)
      values(OLD.org_id, OLD.service_id, OLD.added, OLD.note, now(), 275);
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists service_deleted on org_service_rel;
create trigger service_deleted
  after delete
  on org_service_rel
  for each row
  execute procedure service_deleted();

-- org_name_del (org_names)
drop function if exists org_name_deleted() cascade;
create function org_name_deleted()
  returns trigger
  as $$
    begin
      insert into org_rel_del(org_id, rel_id, added, deleted, table_id)
      values(OLD.org_id, OLD.org_name_id, now(), now(), 249);
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_name_deleted on org_names;
create trigger org_name_deleted
  after delete
  on org_names
  for each row
  execute procedure org_name_deleted();

-- org_del (org)
drop function if exists org_deleted() cascade;
create function org_deleted()
  returns trigger
  as $$
    begin
      insert into org_del(id, org_name_id, update_note, cic_id, updated, service_level)
      values(OLD.id, OLD.org_name_id, OLD.update_note, OLD.cic_id, now(), OLD.service_level);
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_deleted on org;
create trigger org_deleted
  before delete
  on org
  for each row
  execute procedure org_deleted();

-- update_org_name (org.org_name_id)
drop function if exists org_name_updated() cascade;
create function org_name_updated()
  returns trigger
  as $$
    org_id = TD["new"]["id"]
    name_id = TD["new"]["org_name_id"]

    with plpy.subtransaction():
      delete_names = (
        "delete from org_names "
        "where org_id = $1 "
        "and org_name_id = any(select id from tblorgname where orgnametypeid = 1)"
      )
      plan = plpy.prepare(delete_names, ["int"])
      results = plpy.execute(plan, [org_id])

      select_level = (
        "select level from tblorgname "
        "where id = $1"
      )
      plan = plpy.prepare(select_level, ["int"])
      results = plpy.execute(plan, [name_id])
      result = results[0]
      levels = range(result["level"])

      current_id = name_id
      for level in levels:
        if current_id:
          insert_name = (
            "insert into org_names(org_id, org_name_id) "
            "values($1, $2)"
          )
          plan = plpy.prepare(insert_name, ["int", "int"])
          results = plpy.execute(plan, [org_id, current_id])

          select_parent = (
            "select parentid "
            "from tblorgname "
            "where id = $1"
          )
          plan = plpy.prepare(select_parent, ["int"])
          results = plpy.execute(plan, [current_id])
          result = results[0]
          current_id = result["parentid"]
  $$ language plpythonu;

drop trigger if exists org_name_updated on org;
create trigger org_name_updated
  after update of org_name_id
  on org
  for each row
  execute procedure org_name_updated();

-- update_name_parent (tblorgname.ParentID)
drop function if exists name_parent_updated() cascade;
create function name_parent_updated()
  returns trigger
  as $$
    name_id = TD["old"]["id"]
    old_level = TD["old"]["level"]
    old_parent = TD["old"]["parentid"]
    new_parent = TD["new"]["parentid"]

    with plpy.subtransaction():
      if old_parent:
        delete_names = (
          "delete from org_names "
          "where org_id = any(select org_id from org_names where org_name_id = $1) "
          "and org_name_id = any(select id from tblorgname where level between 1 and ($2-1) and orgnametypeid = 1)"
        )
        plan = plpy.prepare(delete_names, ["int", "int"])
        results = plpy.execute(plan, [name_id, old_level])

      if new_parent:
        select_level = (
          "select level from tblorgname "
          "where id = $1"
        )
        plan = plpy.prepare(select_level, ["int"])
        results = plpy.execute(plan, [new_parent])
        result = results[0]
        levels = range(result["level"])

        current_id = new_parent
        for level in levels:
          insert_name = (
            "insert into org_names(org_id, org_name_id) "
            "select distinct org_id, $1 "
            "from org_names "
            "where org_id = any(select org_id from org_names where org_name_id = $2)"
          )
          plan = plpy.prepare(insert_name, ["int", "int"])
          results = plpy.execute(plan, [current_id, name_id])

          select_parent = (
            "select parentid "
            "from tblorgname "
            "where id = $1"
          )
          plan = plpy.prepare(select_parent, ["int"])
          results = plpy.execute(plan, [current_id])
          result = results[0]
          current_id = result["parentid"]
  $$ language plpythonu;

drop trigger if exists name_parent_updated on tblorgname;
create trigger name_parent_updated
  after update of parentid
  on tblorgname
  for each row
  execute procedure name_parent_updated();

-- skipping deleteDeletedPubs

-- org_insert (org)
drop function if exists org_inserted() cascade;
create function org_inserted()
  returns trigger
  as $$
    org_id = TD["new"]["id"]
    name_id = TD["new"]["org_name_id"]

    with plpy.subtransaction():
      select_level = (
        "select level from tblorgname "
        "where id = $1"
      )
      plan = plpy.prepare(select_level, ["int"])
      results = plpy.execute(plan, [name_id])
      result = results[0]
      levels = range(result["level"])

      current_id = name_id
      for level in levels:
        insert_name = (
          "insert into org_names(org_id, org_name_id) "
          "values($1, $2)"
        )
        plan = plpy.prepare(insert_name, ["int", "int"])
        results = plpy.execute(plan, [org_id, current_id])

        select_parent = (
          "select parentid "
          "from tblorgname "
          "where id = $1"
        )
        plan = plpy.prepare(select_parent, ["int"])
        results = plpy.execute(plan, [current_id])
        result = results[0]
        current_id = result["parentid"]
  $$ language plpythonu;

drop trigger if exists org_inserted on org;
create trigger org_inserted
  after insert
  on org
  for each row
  execute procedure org_inserted();

-- skipping pub_org_del
-- skipping MetaIndex

-- make_org_name_sort_key()
-- update_name_sort_parent (tblorgname)
-- create_org_name_sort_key (tblorgname)
drop function if exists name_sort() cascade;
create function name_sort()
  returns trigger
  as $$
    parent_id = TD["new"]["parentid"]
    if parent_id:
      select_parent = (
        "select tblorgname.id as name_id, parent.sort_key as parent_key"
        "from tblorgname join tblorgname as parent on tblorgname.parentid = parent.id "
        "where tblorgname.parentid = $1 "
        "and tblorgname.orgnametypeid = 1 "
        "order by coalesce(tblorgname.sort, tblorgname.name) asc;"
      )
      select_plan = plpy.prepare(select_parent, ["int"])
      select_results = plpy.execute(plan, [parent_id])
    else:
      select_parent = (
        "select tblorgname.id as name_id, parent.sort_key as parent_key"
        "from tblorgname join tblorgname as parent on tblorgname.parentid = parent.id "
        "where tblorgname.parentid is null "
        "and tblorgname.orgnametypeid = 1 "
        "order by coalesce(tblorgname.sort, tblorgname.name) asc;"
      )
      select_plan = plpy.prepare(select_parent)
      select_results = plpy.execute(plan)
    for i, result in enumerate(select_results):
      name_key = str(i).zfill(4)
      update_query = (
        "update tblorgname "
        "set sort_key = coalesce($1, '.', $2) "
        "where id = $3" 
      )
      update_plan = plpy.prepare(update_query, ["text", "text", "int"])
      update_results = plpy.execute(update_plan, [result["parent_key"], name_key, result["name_id"]])
  $$ language plpythonu;

drop trigger if exists name_sort on tblorgname;
create trigger name_sort
  after insert or update of name, parentid, sort
  on tblorgname
  for each row
  execute procedure name_sort();

-- update_child_sort_key (tblorgname)
drop function if exists name_sort_updated() cascade;
create function name_sort_updated()
  returns trigger
  as $$
    begin
      update tblorgname
        set sort_key = concat(NEW.sort_key, substring(tblorgname.sort_key, length(tblorgname.sort_key)-4))
        where parentid = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists name_sort_updated on org_thes;
create trigger name_sort_updated
  after update of sort_key
  on tblorgname
  for each row
  when(NEW.orgnametypeid = 1)
  execute procedure name_sort_updated();


-- insert_uf (org_thes)
drop function if exists org_thes_inserted() cascade;
create function org_thes_inserted()
  returns trigger
  as $$
    begin
      insert into org_thes(org_id, thes_id, official_id)
      select NEW.org_id, rel_id, NEW.thes_id
      from thes_rel
      where rel_type = 'uf'
      and thes_id = NEW.thes_id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_thes_inserted on org_thes;
create trigger org_thes_inserted
  after insert
  on org_thes
  for each row
  when(NEW.thes_id = NEW.official_id)
  execute procedure org_thes_inserted();

-- orgModNameDel (org_names)

-- delete_uf (org_thes)
drop function if exists org_thes_deleted() cascade;
create function org_thes_deleted()
  returns trigger
  as $$
    begin
      delete from org_thes
      where official_id = OLD.official_id
      and org_id = OLD.org_id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_thes_deleted on org_thes;
create trigger org_thes_deleted
  after delete
  on org_thes
  for each row
  when(OLD.thes_id = OLD.official_id)
  execute procedure org_thes_deleted();

-- skipping meta_insert_thes_o
-- skipping meta_insert_thes_o
-- skipping meta_update_thes_o
-- skipping org_meta_insert_res
-- skipping org_meta_delete_res
-- skipping meta_delete_resource
-- skipping meta_insert_resource
-- skipping meta_update_res after

-- orgModContactDel (org_contact_rel)
drop function if exists org_contact_deleted() cascade;
create function org_contact_deleted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_contact_rel
      where id = OLD.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_contact_deleted on org_contact_rel;
create trigger org_contact_deleted
  after delete
  on org_contact_rel
  for each row
  execute procedure org_contact_deleted();

-- orgModCommIns (org_comm_rel)
drop function if exists org_comm_inserted() cascade;
create function org_comm_inserted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_comm_rel
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_comm_inserted on org_comm_rel;
create trigger org_comm_inserted
  after insert
  on org_comm_rel
  for each row
  execute procedure org_comm_inserted();

-- orgModCommDel (org_comm_rel)
drop function if exists org_comm_deleted() cascade;
create function org_comm_deleted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_comm_rel
      where id = OLD.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_comm_deleted on org_comm_rel;
create trigger org_comm_deleted
  after delete
  on org_comm_rel
  for each row
  execute procedure org_comm_deleted();

-- orgModAddressDel (org_address_rel)
drop function if exists org_address_deleted() cascade;
create function org_address_deleted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_address_rel
      where id = OLD.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_address_deleted on org_address_rel;
create trigger org_address_deleted
  after delete
  on org_address_rel
  for each row
  execute procedure org_address_deleted();

-- orgModAddressIns (org_address_rel)
drop function if exists org_address_inserted() cascade;
create function org_address_inserted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_address_rel
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_address_inserted on org_address_rel;
create trigger org_address_inserted
  after delete
  on org_address_rel
  for each row
  execute procedure org_address_inserted();

-- orgModContactIns (org_contact_rel)
drop function if exists org_contact_inserted() cascade;
create function org_contact_inserted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_contact_rel
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_contact_inserted on org_contact_rel;
create trigger org_contact_inserted
  after insert
  on org_contact_rel
  for each row
  execute procedure org_contact_inserted();

-- orgModServiceUp (tblservice)
drop function if exists service_updated() cascade;
create function service_updated()
  returns trigger
  as $$
    service_id = TD["new"]["id"]
    mods = [(
      "update tblservice "
      "set updated = now() "
      "where id = $1"
    ),
    (
      "select org_modified(o.org_id) "
      "from org_service_rel as o join tblservice as s on o.service_id = s.id "
      "where s.id = $1"
    )]
    for mod in mods:
      plan = plpy.prepare(mod, ["int"])
      results = plpy.execute(plan, [service_id])
  $$ language plpythonu;

drop trigger if exists service_updated on tblservice;
create trigger service_updated
  -- excluding tblservice.updated, which gets modified by trigger
  after update of description, eligibility, info, fees, hours, dates, application
  on tblservice
  for each row
  execute procedure service_updated();

-- skipping meta_insert_address

-- orgModNameIns (org_names)
drop function if exists org_name_inserted() cascade;
create function org_name_inserted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_names
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_name_inserted on org_names;
create trigger org_name_inserted
  after insert
  on org_names
  for each row
  execute procedure org_name_inserted();

-- skipping org_meta_insert_address
-- skipping org_meta_delete_address

-- orgModThesInsert (org_thes)
drop function if exists org_thes_inserted() cascade;
create function org_thes_inserted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_thes
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_thes_inserted on org_thes;
create trigger org_thes_inserted
  after insert
  on org_thes
  for each row
  execute procedure org_thes_inserted();

-- orgUpdated (org)
drop function if exists org_updated() cascade;
create function org_updated()
  returns trigger
  as $$
    begin
      insert into orgUpdated(orgid, updated)
      values(NEW.id, NEW.updated)
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_updated on org;
create trigger org_updated
  after update of updated
  on org
  for each row
  execute procedure org_updated();

-- orgModThesDelete (org_thes)
drop function if exists org_thes_deleted() cascade;
create function org_thes_deleted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from org_thes
      where id = OLD.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_thes_deleted on org_thes;
create trigger org_thes_deleted
  after delete
  on org_thes
  for each row
  execute procedure org_thes_deleted();

-- orgModTaxInsert (orgtaxlink)
drop function if exists org_tax_inserted() cascade;
create function org_tax_inserted()
  returns trigger
  as $$
    begin
      select org_modified(orgid)
      from orgtaxlink
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_tax_inserted on orgtaxlink;
create trigger org_tax_inserted
  after insert
  on orgtaxlink
  for each row
  execute procedure org_tax_inserted();

-- orgModTaxDelete (orgtaxlink)
drop function if exists org_tax_deleted() cascade;
create function org_tax_deleted()
  returns trigger
  as $$
    begin
      select org_modified(orgid)
      from orgtaxlink
      where id = OLD.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_tax_deleted on orgtaxlink;
create trigger org_tax_deleted
  after delete
  on orgtaxlink
  for each row
  execute procedure org_tax_deleted();

-- orgModPubContact (pub_org)
drop function if exists pub_org_updated() cascade;
create function pub_org_updated()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from pub_org
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists pub_org_updated on pub_org;
create trigger pub_org_updated
  after update of org_contact_id, isActive
  on pub_org
  for each row
  execute procedure pub_org_updated();

-- updateAddressOrgMod (tbladdress)
drop function if exists address_updated() cascade;
create function address_updated()
  returns trigger
  as $$
    address_id = TD["new"]["id"]
    modify = (
      "select org_modified(o.org_id) "
      "from org_address_rel as o join tbladdress as a on o.address_id = a.id "
      "where a.id = $1"
    )
    plan = plpy.prepare(modify, ["int"])
    results = plpy.execute(plan, [address_id])
  $$ language plpythonu;

drop trigger if exists address_updated on tbladdress;
create trigger address_updated
  after update on tbladdress
  for each row
  execute procedure address_updated();

-- updateCommOrgMod (tblcomm)
drop function if exists comm_updated() cascade;
create function comm_updated()
  returns trigger
  as $$
    comm_id = TD["new"]["id"]
    modify = (
      "select org_modified(o.org_id) "
      "from org_comm_rel as o join tblcomm as c on o.comm_id = c.id "
      "where c.id = $1"
    )
    plan = plpy.prepare(modify, ["int"])
    results = plpy.execute(plan, [comm_id])
  $$ language plpythonu;

drop trigger if exists comm_updated on tblcomm;
create trigger comm_updated
  after update on tblcomm
  for each row
  execute procedure comm_updated();

-- updateContactOrgMod (tblcontact)
drop function if exists contact_updated() cascade;
create function contact_updated()
  returns trigger
  as $$
    contact_id = TD["new"]["id"]
    modify = (
      "select org_modified(o.org_id) "
      "from org_contact_rel as o join tblcontact as c on o.contact_id = c.id "
      "where c.id = $1"
    )
    plan = plpy.prepare(modify, ["int"])
    results = plpy.execute(plan, [contact_id])
  $$ language plpythonu;

drop trigger if exists contact_updated on tblcontact;
create trigger contact_updated
  after update on tblcontact
  for each row
  execute procedure contact_updated();

-- deleteIncomplete (org.iscomplete)
drop function if exists org_is_complete_updated() cascade;
create function org_is_complete_updated()
  returns trigger
  as $$
    begin
      update org set deleted = now() where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists org_is_complete_updated on org;
create trigger org_is_complete_updated
  after update of iscomplete
  on org
  for each row
  when (OLD.iscomplete = 1 and NEW.iscomplete = 0)
  execute procedure org_is_complete_updated();

-- pubOrgInsert (pub_org)
drop function if exists pub_org_inserted() cascade;
create function pub_org_inserted()
  returns trigger
  as $$
    begin
      select org_modified(org_id)
      from pub_org
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists pub_org_inserted on pub_org;
create trigger pub_org_inserted
  after insert
  on pub_org
  for each row
  execute procedure pub_org_inserted();

-- skipping meta_update_address (tbladdress)

-- org_services (ic_site_services)
drop function if exists ic_services_updated() cascade;
create function ic_services_updated()
  returns trigger
  as $$
    begin
      select org_modified(OLD.serviceid);
      select org_modified(NEW.serviceid);
      update org
      set modified = now()
      where id = any(
        select ic_agency_sites.siteid
        from ic_agency_sites join ic_site_services on ic_agency_sites.id join ic_site_services.siteid
        where serviceid in(OLD.serviceid, NEW.serviceid)
      );
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_services_updated on ic_site_services;
create trigger ic_services_updated
  after update
  on ic_site_services
  for each row
  execute procedure ic_services_updated();

-- skipping meta_delete_address

-- mod (taxgroups)
drop function if exists tax_groups_updated() cascade;
create function tax_groups_updated()
  returns trigger
  as $$
    begin
      update taxgroups
      set modified = now()
      where id = NEW.id;
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists tax_groups_updated on ic_site_services;
create trigger tax_groups_updated
  after update of taxgroup, taxid, isactive, haschildren, islocal
  on taxgroups
  for each row
  execute procedure tax_groups_updated();

-- org_sites (ic_agency_sites)
drop function if exists ic_sites_updated() cascade;
create function ic_sites_updated()
  returns trigger
  as $$
    begin
      select org_modified(OLD.siteid);
      select org_modified(NEW.siteid);
      update org
      set modified = now()
      where id = any(
        select orgid
        from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
        where siteid in (OLD.siteid, NEW.siteid)
      );
      update org
      set modified = now()
      where id = any(
        select serviceid
        from ic_site_services
        where siteid in (OLD.siteid, NEW.siteid)
      );
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_sites_updated on ic_agency_sites;
create trigger ic_sites_updated
  after update
  on ic_agency_sites
  for each row
  execute procedure ic_sites_updated();

-- org_services_insert (ic_site_services)
drop function if exists ic_services_inserted() cascade;
create function ic_services_inserted()
  returns trigger
  as $$
    begin
      select org_modified(NEW.serviceid);
      update org
        set modified = now()
        where id = any(
          select ic_agency_sites.siteid
          from ic_agency_sites join ic_site_services on ic_agency_sites.id = ic_site_services.siteid
          where serviceid in (NEW.serviceid)
        );
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_services_inserted on ic_site_services;
create trigger ic_services_inserted
  after insert
  on ic_site_services
  for each row
  execute procedure ic_services_inserted();

-- org_services_delete (ic_site_services)
drop function if exists ic_services_deleted() cascade;
create function ic_services_deleted()
  returns trigger
  as $$
    begin
      select org_modified(OLD.serviceid);
      update org
        set modified = now()
        where id = any(
          select ic_agency_sites.siteid
          from ic_agency_sites join ic_site_services on ic_agency_sites.id = ic_site_services.siteid
          where serviceid in (OLD.serviceid));
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_services_deleted on ic_site_services;
create trigger ic_services_deleted
  after delete
  on ic_site_services
  for each row
  execute procedure ic_services_deleted();

-- org_sites_insert (ic_agency_sites)
drop function if exists ic_sites_inserted() cascade;
create function ic_sites_inserted()
  returns trigger
  as $$
    begin
      select org_modified(NEW.siteid);
      update org
        set modified = now()
        where id = any(
          select orgid
          from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
          where siteid in (NEW.siteid)
        );
      update org 
        set modified = now()
        where id = any(
          select serviceid
          from ic_site_services
          where siteid in (NEW.siteid)
        );
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_sites_inserted on ic_agency_sites;
create trigger ic_sites_inserted
  after insert
  on ic_agency_sites
  for each row
  execute procedure ic_sites_inserted();

-- org_sites_delete (ic_agency_sites)
drop function if exists ic_sites_deleted() cascade;
create function ic_sites_deleted()
  returns trigger
  as $$
    begin
      select org_modified(OLD.siteid);
      update org
        set modified = now()
        where id = any(
          select orgid
          from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
          where siteid in (OLD.siteid)
        );
      update org
        set modified = now()
        where id = any(
          select serviceid
          from ic_site_services
          where siteid in (OLD.siteid)
        );
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_sites_deleted on ic_agency_sites;
create trigger ic_sites_deleted
  after delete
  on ic_agency_sites
  for each row
  execute procedure ic_sites_deleted();

-- org_agency_insert (ic_agencies)
drop function if exists ic_agency_inserted() cascade;
create function ic_agency_inserted()
  returns trigger
  as $$
    begin
      select org_modified(NEW.orgid);
      update org
        set modified = now()
        where id = any(
          select siteid
          from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
          where orgid in (NEW.orgid));
      update org
        set modified = now()
        where id = any(
          select serviceid
          from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
          where orgid in (NEW.orgid)
        );
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_agency_inserted on ic_agencies;
create trigger ic_agency_inserted
  after insert
  on ic_agencies
  for each row
  execute procedure ic_agency_inserted();

-- org_agency_delete (ic_agencies)
drop function if exists ic_agency_deleted() cascade;
create function ic_agency_deleted()
  returns trigger
  as $$
    begin
      select org_modified(OLD.orgid);
      update org
        set modified = now()
        where id = any(
          select siteid
          from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
          where orgid in (OLD.orgid)
        );
      update org
        set modified = now()
        where id = any(
          select serviceid
          from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
          where orgid in (OLD.orgid)
        );
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_agency_deleted on ic_agencies;
create trigger ic_agency_deleted
  after delete
  on ic_agencies
  for each row
  execute procedure ic_agency_deleted();

-- org_agency (ic_agencies)
drop function if exists ic_agency_updated() cascade;
create function ic_agency_updated()
  returns trigger
  as $$
    begin
      select org_modified(OLD.orgid);
      select org_modified(NEW.orgid);
      update org
       set modified = now()
       where id = any(
        select siteid from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
        where orgid in (OLD.orgid, NEW.orgid)
      );
      update org
        set modified = now() 
        where id = any(
          select serviceid
          from ic_agencies join ic_agency_sites on ic_agencies.id = ic_agency_sites.agencyid
          where orgid in (OLD.orgid, NEW.orgid)
        );
      return null;
    end;
  $$ language plpgsql;

drop trigger if exists ic_agency_updated on ic_agencies;
create trigger ic_agency_updated
  after update
  on ic_agencies
  for each row
  execute procedure ic_agency_updated();

-- skipping org_meta_insert_site
-- skipping org_meta_delete_site
