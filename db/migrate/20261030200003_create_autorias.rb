class CreateAutorias < ActiveRecord::Migration[8.1]
  def change
    create_table :autorias do |t|
      t.references :parlamentar, null: false, foreign_key: true
      t.references :proposta, null: false, foreign_key: true
      t.string :tipo_autoria, default: "Autor"

      t.timestamps
    end

    add_index :autorias, [ :parlamentar_id, :proposta_id ], unique: true
  end
end

