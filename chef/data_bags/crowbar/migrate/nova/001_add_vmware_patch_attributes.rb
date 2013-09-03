def upgrade ta, td, a, d
  a['esxi'] = {}
  a['esxi']['host'] = ta['esxi']['host']
  a['esxi']['login'] = ta['esxi']['login']
  a['esxi']['password'] = ta['esxi']['password']
  a['esxi']['cluster'] = ta['esxi']['cluster']
  a['esxi']['datastore'] = ta['esxi']['datastore']
  a['esxi']['interface'] = ta['esxi']['interface']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('esxi')
  return a, d
end
