def upgrade ta, td, a, d
  a['zvm'] = ta['zvm']
  d['element_states'] = td['element_states']
  d['element_order'] = td['element_order']
  d['element_run_list_order'] = td['element_run_list_order']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('zvm')
  d['element_states'].delete('nova-multi-compute-zvm')
  d['elements'].delete('nova-multi-compute-zvm')
  d['element_order'][1].delete('nova-multi-compute-zvm')
  d['element_run_list_order'].delete('nova-multi-compute-zvm')
  return a, d
end
