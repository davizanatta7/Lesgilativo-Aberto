class AddPropostasCountToParlamentares < ActiveRecord::Migration[8.1]
  def up
    add_column :parlamentares, :propostas_count, :integer, default: 0, null: false
    add_index :parlamentares, :propostas_count

    execute <<~SQL
      UPDATE parlamentares
      SET propostas_count = (
        SELECT COUNT(*)
        FROM autorias
        WHERE autorias.parlamentar_id = parlamentares.id
      )
    SQL
  end

  def down
    remove_index :parlamentares, :propostas_count
    remove_column :parlamentares, :propostas_count
  end
end

