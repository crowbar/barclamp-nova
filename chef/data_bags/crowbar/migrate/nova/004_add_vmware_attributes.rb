# -*- encoding : utf-8 -*-
def upgrade ta, td, a, d
  a['vcenter'] = {}
  a['vcenter']['host'] = ta['vcenter']['host']
  a['vcenter']['user'] = ta['vcenter']['user']
  a['vcenter']['password'] = ta['vcenter']['password']
  a['vcenter']['clusters'] = ta['vcenter']['clusters']
  a['vcenter']['interface'] = ta['vcenter']['interface']
  unless a['esxi'].nil?
    a['vcenter']['host'] = a['esxi']['host']
    a['vcenter']['user'] = a['esxi']['login']
    a['vcenter']['password'] = a['esxi']['password']
    a['vcenter']['clusters'] = [ a['esxi']['cluster'] ]
    a['vcenter']['interface'] = a['esxi']['interface'] unless a['esxi']['interface'].nil?
    a.delete('esxi')
  end
  d['element_states'] = td['element_states']
  d['element_order'] = td['element_order']
  d['element_run_list_order'] = td['element_run_list_order']
  unless d['elements']['nova-compute-esxi'].nil?
    d['elements']['nova-compute-vmware'] = d['elements']['nova-compute-esxi']
    d['elements'].delete('nova-compute-esxi')
  end
  return a, d
end

def downgrade ta, td, a, d
   a['esxi'] = {}
   a['esxi']['host'] = ta['esxi']['host']
   a['esxi']['login'] = ta['esxi']['login']
   a['esxi']['password'] = ta['esxi']['password']
   a['esxi']['cluster'] = ta['esxi']['cluster']
   a['esxi']['datastore'] = ta['esxi']['datastore']
   a['esxi']['interface'] = ta['esxi']['interface']
  unless a['vcenter'].nil?
    a['esxi']['host'] = a['vcenter']['host']
    a['esxi']['login'] = a['vcenter']['user']
    a['esxi']['password'] = a['vcenter']['password']
    a['esxi']['cluster'] = a['vcenter']['clusters'][0] || ""
    a['esxi']['datastore'] = ta['esxi']['datastore']
    a['esxi']['interface'] = a['vcenter']['interface']
    a.delete('vcenter')
  end
  d['element_states'] = td['element_states']
  d['element_order'] = td['element_order']
  d['element_run_list_order'] = td['element_run_list_order']
  unless d['elements']['nova-compute-vmware'].nil?
    d['elements']['nova-compute-esxi'] = d['elements']['nova-compute-vmware']
    d['elements'].delete('nova-compute-vmware')
  end

  return a, d
end
