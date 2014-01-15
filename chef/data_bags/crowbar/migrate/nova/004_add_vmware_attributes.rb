def upgrade ta, td, a, d
  a['vcenter'] = {}
  a['vcenter']['host'] = ta['vcenter']['host']
  a['vcenter']['user'] = ta['vcenter']['user']
  a['vcenter']['password'] = ta['vcenter']['password']
  a['vcenter']['clusters'] = ta['vcenter']['clusters']
  a['vcenter']['interface'] = ta['vcenter']['interface']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('vcenter')
  return a, d
end
