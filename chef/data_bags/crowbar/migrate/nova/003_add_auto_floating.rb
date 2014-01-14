
def upgrade ta, td, a, d
  a[:auto_assign_floating_ip] = ta[:auto_assign_floating_ip]
  return a, d
end

def downgrade ta, td, a, d
  a.delete('auto_assign_floating_ip')
  return a, d
end
