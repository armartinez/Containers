//
//  FormList+Editor.swift
//  Containers
//
//  Created by Axel Martinez on 2026/08/09.
//

import SwiftUI

// MARK: - Editor sheet

extension FormList {
    var editorPresentation: Binding<Bool> {
        Binding(
            get: { selection.editorTarget != nil },
            set: { isPresented in
                if !isPresented {
                    closeEditor()
                }
            }
        )
    }

    @ViewBuilder
    var editor: some View {
        if let binding = editorItemBinding {
            FormSheet(
                title: editorTitle,
                description: editorDescription,
                primaryButtonTitle: editorPrimaryButtonTitle,
                showsCancelButton: isEditingNewItem,
                isPrimaryButtonDisabled: !canSave(binding.wrappedValue),
                onSave: editorSaveAction
            ) {
                editorContent(binding)
            }
        }
    }

    var isEditingNewItem: Bool {
        if case .new = selection.editorTarget {
            return true
        }

        return false
    }

    var editorPrimaryButtonTitle: String {
        isEditingNewItem ? "Save" : "Done"
    }

    var editorTitle: String {
        isEditingNewItem ? addLabel : (title ?? addLabel)
    }

    var editorSaveAction: (() -> Void)? {
        guard isEditingNewItem else {
            return nil
        }

        return saveNewEditingItem
    }

    var editorItemBinding: Binding<Item>? {
        guard let target = selection.editorTarget else {
            return nil
        }

        switch target {
        case .new:
            return Binding(
                get: {
                    guard case .new(let item) = self.selection.editorTarget else {
                        return newItem()
                    }

                    return item
                },
                set: { selection.editorTarget = .new($0) }
            )
        case .existing(let id):
            return itemBinding(for: id)
        }
    }

    func openEditor(for id: Item.ID) {
        selection.edit(id)
    }

    func closeEditor() {
        selection.closeEditor()
    }

    func saveNewEditingItem() {
        guard case .new(let item) = selection.editorTarget else {
            return
        }

        selection.append(item, to: &items)
        selection.closeEditor()
    }
}
