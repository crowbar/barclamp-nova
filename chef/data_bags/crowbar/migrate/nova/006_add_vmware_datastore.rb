def upgrade ta, td, a, d
  a['vcenter']['datastore'] = ta['vcenter']['datastore']
  return a, d
end

def downgrade ta, td, a, d
  a['vcenter'].delete('datastore')
  return a, d
end
